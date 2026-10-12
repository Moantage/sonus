import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Why an HTTP read failed.
public enum HTTPClientError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The URL breaks ``NetworkPolicy``.
    case blockedURL(URL)
    /// The server answered with a status that isn't success.
    case status(HTTPResponseHead)
    /// 416: the range starts past the end of the file.
    case rangeNotSatisfiable
    /// A 206 response that doesn't match the requested range.
    case unexpectedRange
    case invalidResponse
    case tooLarge(limit: Int)
    case cancelled
    /// A transport error, with its `NSURLErrorDomain` code.
    case transport(code: Int, message: String)

    public var statusCode: Int? {
        if case .status(let head) = self { head.statusCode } else { nil }
    }

    public var description: String {
        switch self {
        case .blockedURL(let url):
            "\(url.removingCredentials.absoluteString) isn't allowed: remote hosts must use https."
        case .status(let head):
            "The server answered HTTP \(head.statusCode)."
        case .rangeNotSatisfiable:
            "The server couldn't return that part of the file."
        case .unexpectedRange:
            "The server returned the wrong part of the file."
        case .invalidResponse:
            "The server's response wasn't valid HTTP."
        case .tooLarge(let limit):
            "The response was larger than \(limit) bytes."
        case .cancelled:
            "The request was cancelled."
        case .transport(_, let message):
            message
        }
    }

    public static func from(_ error: any Error) -> HTTPClientError {
        if let error = error as? HTTPClientError {
            return error
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return .cancelled
        }
        return .transport(code: nsError.code, message: nsError.localizedDescription)
    }
}

/// Callbacks for one streamed read. They run on the client's serial delegate queue.
public struct HTTPStreamHandler: Sendable {
    /// Called once with the response head. Return false to stop after it (the read then
    /// completes without an error).
    public var onResponse: @Sendable (HTTPResponseHead) -> Bool
    /// Called with the body, already trimmed to the requested range.
    public var onData: @Sendable (Data) -> Void
    /// Called once at the end, with nil on success.
    public var onComplete: @Sendable (HTTPClientError?) -> Void

    public init(
        onResponse: @escaping @Sendable (HTTPResponseHead) -> Bool = { _ in true },
        onData: @escaping @Sendable (Data) -> Void,
        onComplete: @escaping @Sendable (HTTPClientError?) -> Void
    ) {
        self.onResponse = onResponse
        self.onData = onData
        self.onComplete = onComplete
    }
}

/// A running read. Cancelling it reports ``HTTPClientError/cancelled``.
public final class HTTPStreamTask: @unchecked Sendable {
    private let task: URLSessionTask

    init(task: URLSessionTask) {
        self.task = task
    }

    public func cancel() {
        task.cancel()
    }
}

/// Reads byte ranges over HTTP, streaming the body as it arrives.
///
/// It adds a secret header only for hosts its ``RequestAuthorization`` allows, re-checks every
/// redirect (dropping the header for other hosts, refusing insecure targets), asks for
/// uncompressed bodies, and copes with servers that ignore `Range` by skipping bytes itself.
public final class StreamingHTTPClient: @unchecked Sendable {
    private let session: URLSession
    private let delegate: StreamingSessionDelegate

    public init(configuration: URLSessionConfiguration = StreamingHTTPClient.defaultConfiguration()) {
        let delegate = StreamingSessionDelegate()
        let queue = OperationQueue()
        queue.name = "SonusCore.StreamingHTTPClient"
        queue.maxConcurrentOperationCount = 1
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
    }

    /// No cookies or caching: audio is large and every request is explicit.
    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        return configuration
    }

    /// Ends the session. The client can't be used afterwards.
    public func invalidate() {
        session.invalidateAndCancel()
    }

    /// Starts a streamed read of `range` (or the whole resource).
    /// - Throws: ``HTTPClientError/blockedURL(_:)`` when `url` breaks ``NetworkPolicy``.
    @discardableResult
    public func stream(
        _ url: URL,
        range: ByteRange? = nil,
        authorization: RequestAuthorization? = nil,
        headers: [String: String] = [:],
        handler: HTTPStreamHandler
    ) throws -> HTTPStreamTask {
        guard NetworkPolicy.allows(url) else {
            throw HTTPClientError.blockedURL(url)
        }
        let request = RangedRequest.make(url: url, range: range, authorization: authorization, headers: headers)
        let task = session.dataTask(with: request)
        let state = StreamTaskState(
            handler: handler,
            range: range,
            authorization: authorization,
            carriedHeaders: RangedRequest.carriedHeaders(range: range, extra: headers)
        )
        delegate.register(state, for: task.taskIdentifier)
        task.resume()
        return HTTPStreamTask(task: task)
    }

    /// Reads `range` (or the whole resource) into memory.
    public func data(
        _ url: URL,
        range: ByteRange? = nil,
        authorization: RequestAuthorization? = nil,
        headers: [String: String] = [:],
        maxBytes: Int = 64 * 1024 * 1024
    ) async throws -> (data: Data, head: HTTPResponseHead) {
        let collector = DataCollector(limit: maxBytes)
        let taskBox = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let handler = HTTPStreamHandler(
                    onResponse: { head in collector.accept(head) },
                    onData: { chunk in
                        if !collector.append(chunk) {
                            taskBox.cancel()
                        }
                    },
                    onComplete: { error in
                        continuation.resume(with: collector.result(error: error))
                    }
                )
                do {
                    let task = try stream(url, range: range, authorization: authorization, headers: headers, handler: handler)
                    taskBox.set(task)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            taskBox.cancel()
        }
    }
}

// MARK: - Session delegate

private final class StreamTaskState: @unchecked Sendable {
    let handler: HTTPStreamHandler
    let range: ByteRange?
    let authorization: RequestAuthorization?
    let carriedHeaders: [String: String]
    // Mutated only on the session's serial delegate queue.
    var bytesToSkip: Int64 = 0
    var bytesRemaining: Int64?
    var stoppedEarly = false
    var failure: HTTPClientError?

    init(handler: HTTPStreamHandler, range: ByteRange?, authorization: RequestAuthorization?, carriedHeaders: [String: String]) {
        self.handler = handler
        self.range = range
        self.authorization = authorization
        self.carriedHeaders = carriedHeaders
    }
}

private final class StreamingSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [Int: StreamTaskState] = [:]

    func register(_ state: StreamTaskState, for identifier: Int) {
        lock.withLock { states[identifier] = state }
    }

    private func state(for task: URLSessionTask) -> StreamTaskState? {
        lock.withLock { states[task.taskIdentifier] }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let state = state(for: task) else {
            completionHandler(nil)
            return
        }
        completionHandler(RedirectPolicy.follow(request, authorization: state.authorization, headers: state.carriedHeaders))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let state = state(for: dataTask) else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            state.failure = .invalidResponse
            completionHandler(.cancel)
            return
        }
        let head = HTTPResponseHead(http)
        if let failure = Self.prepare(state, for: head) {
            state.failure = failure
            completionHandler(.cancel)
            return
        }
        if state.handler.onResponse(head) {
            completionHandler(.allow)
        } else {
            state.stoppedEarly = true
            completionHandler(.cancel)
        }
    }

    /// Sets up skipping and trimming for the response, or returns why it can't be used.
    private static func prepare(_ state: StreamTaskState, for head: HTTPResponseHead) -> HTTPClientError? {
        switch head.statusCode {
        case 206:
            guard let range = state.range, let contentRange = head.contentRange, contentRange.first == range.lowerBound else {
                return .unexpectedRange
            }
            state.bytesRemaining = range.length
        case 200..<300:
            // A server that ignores Range sends the whole file from byte 0.
            state.bytesToSkip = state.range?.lowerBound ?? 0
            state.bytesRemaining = state.range?.length
        case 416:
            return .rangeNotSatisfiable
        default:
            return .status(head)
        }
        return nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let state = state(for: dataTask), !state.stoppedEarly else { return }
        var chunk = data
        if state.bytesToSkip > 0 {
            let skipped = min(Int64(chunk.count), state.bytesToSkip)
            chunk = Data(chunk.dropFirst(Int(skipped)))
            state.bytesToSkip -= skipped
        }
        if let remaining = state.bytesRemaining {
            if Int64(chunk.count) >= remaining {
                chunk = Data(chunk.prefix(Int(remaining)))
                state.bytesRemaining = 0
                state.stoppedEarly = true
            } else {
                state.bytesRemaining = remaining - Int64(chunk.count)
            }
        }
        if !chunk.isEmpty {
            state.handler.onData(chunk)
        }
        if state.stoppedEarly {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let state = lock.withLock { states.removeValue(forKey: task.taskIdentifier) }
        guard let state else { return }
        if let failure = state.failure {
            state.handler.onComplete(failure)
        } else if state.stoppedEarly {
            state.handler.onComplete(nil)
        } else {
            state.handler.onComplete(error.map(HTTPClientError.from))
        }
    }
}

// MARK: - Helpers for `data(_:)`

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var head: HTTPResponseHead?
    private var failure: HTTPClientError?

    init(limit: Int) {
        self.limit = limit
    }

    func accept(_ head: HTTPResponseHead) -> Bool {
        lock.withLock {
            self.head = head
            if let length = head.contentLength, length > Int64(limit) {
                failure = .tooLarge(limit: limit)
                return false
            }
            return true
        }
    }

    /// Returns false once the limit is exceeded.
    func append(_ chunk: Data) -> Bool {
        lock.withLock {
            data.append(chunk)
            if data.count > limit {
                failure = .tooLarge(limit: limit)
                return false
            }
            return true
        }
    }

    func result(error: HTTPClientError?) -> Result<(data: Data, head: HTTPResponseHead), any Error> {
        lock.withLock {
            if let failure {
                return .failure(failure)
            }
            if let error {
                return .failure(error)
            }
            guard let head else {
                return .failure(HTTPClientError.invalidResponse)
            }
            return .success((data, head))
        }
    }
}

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: HTTPStreamTask?
    private var isCancelled = false

    func set(_ task: HTTPStreamTask) {
        let cancelNow = lock.withLock {
            self.task = task
            return isCancelled
        }
        if cancelNow {
            task.cancel()
        }
    }

    func cancel() {
        let task = lock.withLock {
            isCancelled = true
            return self.task
        }
        task?.cancel()
    }
}
