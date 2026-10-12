import Foundation
import SonusCore

/// Downloads songs from their source so they play offline. Free for everyone: offline play is not
/// a Premium feature.
///
/// A song is "downloaded" when its audio file exists locally (see `Song.isDownloadedLocally`);
/// imported songs already are. Downloads run on a background `URLSession`
/// (``BackgroundDownloadSession``), so they continue while the app is in the background. They
/// report real progress, can be cancelled, and resume where they stopped when the server
/// supports range requests.
///
/// Addresses follow `NetworkPolicy`: https anywhere, plain http only on the local network. A
/// source's secret header goes only to the hosts it's meant for, and redirects are resolved before
/// an authenticated download starts, because background sessions follow redirects without asking.
@MainActor
final class DownloadManager: ObservableObject {

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(String)
    }

    @Published private(set) var states: [Song.ID: State] = [:]

    private let session = BackgroundDownloadSession.shared
    private var tasks: [Song.ID: URLSessionDownloadTask] = [:]
    private var authorizedTasks = Set<Song.ID>()
    private var starting = Set<Song.ID>()
    private var waiters: [Song.ID: [CheckedContinuation<String?, Never>]] = [:]
    /// Resume data for downloads with a secret header: it contains that header, so it stays in
    /// memory. Other resume data is saved in Caches.
    private var memoryResumeData: [Song.ID: Data] = [:]

    init() {
        session.onEvent = { [weak self] event in self?.handle(event) }
        Task { await reconnect() }
    }

    /// Current state for a song, derived from disk if not tracked in memory.
    func state(for song: Song) -> State {
        if let tracked = states[song.id] { return tracked }
        return song.isDownloadedLocally ? .downloaded : .notDownloaded
    }

    func isDownloaded(_ song: Song) -> Bool {
        if case .downloaded = state(for: song) { return true }
        return song.isDownloadedLocally
    }

    /// True while a song is downloading.
    func isDownloading(_ song: Song) -> Bool {
        tasks[song.id] != nil || starting.contains(song.id)
    }

    /// Downloads a cloud-only song's audio to local storage, or joins a download already running.
    /// - Returns: the local file name to persist on the Song, or nil on failure or cancellation.
    @discardableResult
    func download(_ song: Song) async -> String? {
        guard !song.isDownloadedLocally else {
            states[song.id] = .downloaded
            return song.fileName
        }
        guard let remoteURL = song.remoteURL else {
            states[song.id] = .failed("This track isn't hosted in the cloud yet.")
            return nil
        }
        // `remoteURL` can come from a synced snapshot or a source, so only allow https, or plain
        // http to the local network. Never file:// or other schemes.
        guard NetworkPolicy.allows(remoteURL) else {
            states[song.id] = .failed("This track's download link isn't secure.")
            return nil
        }

        return await withCheckedContinuation { continuation in
            waiters[song.id, default: []].append(continuation)
            guard tasks[song.id] == nil, !starting.contains(song.id) else { return }
            starting.insert(song.id)
            states[song.id] = .downloading(progress: 0)
            Task { await start(song, url: remoteURL) }
        }
    }

    /// Removes a downloaded file to free space (keeps the library entry so it
    /// can be re-downloaded later). Songs that exist only on this device are left alone.
    func removeDownload(_ song: Song) {
        guard song.remoteURL != nil else { return }
        try? FileManager.default.removeItem(at: AppPaths.fileURL(for: song))
        discardResumeData(for: song.id)
        states[song.id] = .notDownloaded
    }

    /// Stops a download. The next `download(_:)` resumes where it stopped when it can.
    func cancel(_ song: Song) {
        let songID = song.id
        starting.remove(songID)
        if let task = tasks.removeValue(forKey: songID) {
            let isAuthorized = authorizedTasks.remove(songID) != nil
            task.cancel { [weak self] resumeData in
                DispatchQueue.main.async { self?.keepResumeData(resumeData, for: songID, isAuthorized: isAuthorized) }
            }
        }
        if case .downloading = states[songID] { states[songID] = .notDownloaded }
        resumeWaiters(for: songID, with: nil)
    }

    // MARK: - Running downloads

    private func start(_ song: Song, url: URL) async {
        let sources = SourceStore.shared
        let authorization = sources.source(id: song.sourceID).flatMap(sources.authorization(for:))
        var target = url
        if let authorization {
            do {
                target = try await finalURL(of: url, authorization: authorization, client: sources.httpClient)
            } catch {
                starting.remove(song.id)
                fail(song.id, message: Self.message(for: error))
                return
            }
        }
        // Cancelled while the redirect check ran.
        guard starting.remove(song.id) != nil else { return }

        let request = RangedRequest.make(url: target, range: nil, authorization: authorization)
        let isAuthorized = request.value(forHTTPHeaderField: "Authorization") != nil
        let ticket = DownloadTicket(songID: song.id, fileName: song.fileName, sha256: song.remoteSHA256, isAuthorized: isAuthorized)
        let resumeData = memoryResumeData.removeValue(forKey: song.id) ?? (isAuthorized ? nil : savedResumeData(for: song.id))
        tasks[song.id] = session.start(request, ticket: ticket, resumeData: resumeData)
        if isAuthorized {
            authorizedTasks.insert(song.id)
        }
    }

    /// Follows redirects in the foreground, where `RedirectPolicy` drops the secret header for
    /// other hosts, and returns where the file really is.
    private func finalURL(of url: URL, authorization: RequestAuthorization, client: StreamingHTTPClient) async throws -> URL {
        let head = try await client.data(url, range: ByteRange(lowerBound: 0, upperBound: 0), authorization: authorization).head
        return head.url ?? url
    }

    private func handle(_ event: BackgroundDownloadSession.Event) {
        switch event {
        case .progress(let songID, let fraction):
            states[songID] = .downloading(progress: fraction)
        case .finished(let songID, let fileName):
            tasks[songID] = nil
            authorizedTasks.remove(songID)
            discardResumeData(for: songID)
            states[songID] = .downloaded
            resumeWaiters(for: songID, with: fileName)
        case .failed(let songID, let message, let resumeData, let isAuthorized):
            tasks[songID] = nil
            authorizedTasks.remove(songID)
            if resumeData != nil {
                keepResumeData(resumeData, for: songID, isAuthorized: isAuthorized)
            } else {
                discardResumeData(for: songID)
            }
            fail(songID, message: message)
        case .cancelled(let songID):
            tasks[songID] = nil
            authorizedTasks.remove(songID)
            if case .downloading = states[songID] { states[songID] = .notDownloaded }
            resumeWaiters(for: songID, with: nil)
        }
    }

    /// Picks up transfers that kept running while the app was closed.
    private func reconnect() async {
        for task in await session.downloadTasks() {
            guard let ticket = DownloadTicket(task: task), task.state == .running || task.state == .suspended else { continue }
            tasks[ticket.songID] = task
            if ticket.isAuthorized {
                authorizedTasks.insert(ticket.songID)
            }
            let expected = task.countOfBytesExpectedToReceive
            let fraction = expected > 0 ? Double(task.countOfBytesReceived) / Double(expected) : 0
            states[ticket.songID] = .downloading(progress: fraction)
        }
    }

    private func fail(_ songID: Song.ID, message: String) {
        states[songID] = .failed(message)
        resumeWaiters(for: songID, with: nil)
    }

    private func resumeWaiters(for songID: Song.ID, with fileName: String?) {
        for waiter in waiters.removeValue(forKey: songID) ?? [] {
            waiter.resume(returning: fileName)
        }
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? HTTPClientError else { return "Download failed. Check your connection." }
        if case .status(let head) = error, let host = head.url?.host?.lowercased(),
           GitHubEndpoints.github.hosts.contains(host),
           let gitHubError = GitHubAPIError.classify(statusCode: head.statusCode, headers: head.headers, hasToken: true) {
            return gitHubError.description
        }
        if case .transport(let code, _) = error, let message = StreamingErrorMessages.transportMessage(code: code) {
            return message
        }
        return error.description
    }

    // MARK: - Resume data

    private func resumeDataURL(for songID: Song.ID) -> URL {
        AppPaths.downloadResumeDirectory.appendingPathComponent("\(songID.uuidString).resume")
    }

    private func keepResumeData(_ data: Data?, for songID: Song.ID, isAuthorized: Bool) {
        guard let data else { return }
        if isAuthorized {
            memoryResumeData[songID] = data
        } else {
            try? data.write(to: resumeDataURL(for: songID), options: .atomic)
        }
    }

    private func savedResumeData(for songID: Song.ID) -> Data? {
        try? Data(contentsOf: resumeDataURL(for: songID))
    }

    private func discardResumeData(for songID: Song.ID) {
        memoryResumeData[songID] = nil
        try? FileManager.default.removeItem(at: resumeDataURL(for: songID))
    }
}
