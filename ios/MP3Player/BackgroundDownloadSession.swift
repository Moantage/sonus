import CryptoKit
import Foundation
import SonusCore

/// What a download task is for. Saved in the task's `taskDescription`, so downloads that finish
/// after iOS relaunched the app still land in the right place. It holds no secrets.
struct DownloadTicket: Codable {
    let songID: UUID
    let fileName: String
    /// Lowercase hex SHA-256 the source published; the file is checked against it.
    let sha256: String?
    /// True when the request carries a secret header. Its resume data then contains that header,
    /// so it's kept in memory only, never written to disk.
    let isAuthorized: Bool

    init(songID: UUID, fileName: String, sha256: String?, isAuthorized: Bool) {
        self.songID = songID
        self.fileName = fileName
        self.sha256 = sha256
        self.isAuthorized = isAuthorized
    }

    init?(task: URLSessionTask) {
        guard let text = task.taskDescription, let ticket = try? JSONDecoder().decode(DownloadTicket.self, from: Data(text.utf8)) else {
            return nil
        }
        self = ticket
    }

    var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// The app's single background `URLSession` for song downloads. Transfers keep going while the app
/// is suspended or terminated; iOS relaunches it to deliver the result.
///
/// The delegate checks and moves each finished file itself (HTTP status, Git LFS pointer, SHA-256),
/// so that works even before any `DownloadManager` exists. Events reach the manager on the main
/// thread.
final class BackgroundDownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.novoralabs.mp3player.downloads"
    static let shared = BackgroundDownloadSession()

    enum Event {
        case progress(songID: UUID, fraction: Double)
        case finished(songID: UUID, fileName: String)
        case failed(songID: UUID, message: String, resumeData: Data?, isAuthorized: Bool)
        case cancelled(songID: UUID)
    }

    /// Set by `DownloadManager`; called on the main thread.
    @MainActor var onEvent: (@MainActor (Event) -> Void)?

    private let lock = NSLock()
    private var systemCompletionHandler: (() -> Void)?
    // Touched only on the session's serial delegate queue.
    private var outcomes: [Int: Event] = [:]
    private var reportedProgress: [Int: Double] = [:]

    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        let queue = OperationQueue()
        queue.name = "com.novoralabs.sonus.downloads"
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    func start(_ request: URLRequest, ticket: DownloadTicket, resumeData: Data?) -> URLSessionDownloadTask {
        let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: request)
        task.taskDescription = ticket.encoded
        task.resume()
        return task
    }

    func downloadTasks() async -> [URLSessionDownloadTask] {
        await session.allTasks.compactMap { $0 as? URLSessionDownloadTask }
    }

    /// Called from the app delegate when iOS relaunches the app for this session's events.
    func handleEvents(for identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Self.identifier else {
            completionHandler()
            return
        }
        lock.withLock { systemCompletionHandler = completionHandler }
        _ = session // Reconnects to the transfers so their events are delivered.
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let ticket = DownloadTicket(task: downloadTask) else { return }
        // The file at `location` is deleted when this method returns, so move it now.
        outcomes[downloadTask.taskIdentifier] = Self.place(location, response: downloadTask.response, ticket: ticket)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0, let ticket = DownloadTicket(task: downloadTask) else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        let last = reportedProgress[downloadTask.taskIdentifier] ?? -1
        guard fraction - last >= 0.01 || fraction >= 1 else { return }
        reportedProgress[downloadTask.taskIdentifier] = fraction
        deliver(.progress(songID: ticket.songID, fraction: fraction))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        reportedProgress[task.taskIdentifier] = nil
        guard let ticket = DownloadTicket(task: task) else { return }
        if let outcome = outcomes.removeValue(forKey: task.taskIdentifier) {
            deliver(outcome)
            return
        }
        let nsError = error.map { $0 as NSError }
        if nsError?.domain == NSURLErrorDomain && nsError?.code == NSURLErrorCancelled {
            deliver(.cancelled(songID: ticket.songID))
            return
        }
        let resumeData = nsError?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let message = nsError.map { StreamingErrorMessages.transportMessage(code: $0.code) ?? "Download failed. Check your connection." }
            ?? "Download failed."
        deliver(.failed(songID: ticket.songID, message: message, resumeData: resumeData, isAuthorized: ticket.isAuthorized))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = lock.withLock {
            defer { systemCompletionHandler = nil }
            return systemCompletionHandler
        }
        DispatchQueue.main.async { handler?() }
    }

    // MARK: - Placing files

    private func deliver(_ event: Event) {
        DispatchQueue.main.async {
            if case .finished(let songID, _) = event {
                NotificationCenter.default.post(name: .sonusDownloadCompleted, object: songID)
            }
            self.onEvent?(event)
        }
    }

    /// Checks a finished download and moves it into ImportedSongs.
    private static func place(_ location: URL, response: URLResponse?, ticket: DownloadTicket) -> Event {
        func failure(_ message: String) -> Event {
            .failed(songID: ticket.songID, message: message, resumeData: nil, isAuthorized: ticket.isAuthorized)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return failure(statusMessage(for: http, hasToken: ticket.isAuthorized))
        }
        let size = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size <= LFSPointer.maxSize, let data = try? Data(contentsOf: location), LFSPointer.parse(data) != nil {
            return failure("The server sent a Git LFS pointer instead of the song. Refresh the source and try again.")
        }
        if let expected = ticket.sha256, let actual = sha256(of: location), actual != expected {
            return failure("The download doesn't match the source's checksum. Try again.")
        }

        var destination = AppPaths.importedSongsDirectory.appendingPathComponent((ticket.fileName as NSString).lastPathComponent)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            // Playable while the phone is locked, and re-downloadable, so not in iCloud backups.
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                   ofItemAtPath: destination.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? destination.setResourceValues(values)
            return .finished(songID: ticket.songID, fileName: destination.lastPathComponent)
        } catch {
            return failure("Couldn't save the download. Check your free space.")
        }
    }

    private static func statusMessage(for response: HTTPURLResponse, hasToken: Bool) -> String {
        let head = HTTPResponseHead(response)
        if let host = response.url?.host?.lowercased(), GitHubEndpoints.github.hosts.contains(host),
           let error = GitHubAPIError.classify(statusCode: head.statusCode, headers: head.headers, hasToken: hasToken) {
            return error.description
        }
        switch head.statusCode {
        case 401, 403:
            return StreamingErrorMessages.denied
        case 404, 410:
            return StreamingErrorMessages.notFound
        default:
            return "Download failed (HTTP \(head.statusCode))."
        }
    }

    private static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
