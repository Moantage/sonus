import AVFoundation
import Foundation
import SonusCore

/// Streams audio through Sonus's own HTTP client instead of AVPlayer's.
///
/// `AVPlayer` can't reliably add an `Authorization` header (`AVURLAssetHTTPHeaderFieldsKey` is
/// undocumented), and some hosts (GitHub raw) serve audio as `application/octet-stream`. Assets
/// built here use a custom URL scheme (`sonus-auth://`), so AVFoundation hands every byte-range
/// request to this delegate. Each one becomes a ranged `URLSession` request that carries the
/// source's secret header only to the hosts its ``RequestAuthorization`` allows. Seeking works
/// because AVFoundation simply asks for other ranges. The class doesn't care what kind of secret it
/// sends, so Sonus Server tokens and private buckets can use it later.
final class AuthorizedResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.novoralabs.sonus.resource-loader")

    private let client: StreamingHTTPClient
    private let authorization: RequestAuthorization?
    private let contentType: String
    /// Running requests, keyed by loading request. Touched only on `queue`, which is what makes the
    /// class safe to share with the HTTP client's callbacks.
    private var tasks: [ObjectIdentifier: HTTPStreamTask] = [:]

    private init(client: StreamingHTTPClient, authorization: RequestAuthorization?, contentType: String) {
        self.client = client
        self.authorization = authorization
        self.contentType = contentType
    }

    /// An asset that streams `url` through a new loader. Keep the loader alive as long as the
    /// asset: the asset only holds it weakly.
    static func makeAsset(
        for url: URL,
        client: StreamingHTTPClient,
        authorization: RequestAuthorization?,
        contentType: String
    ) -> (asset: AVURLAsset, loader: AuthorizedResourceLoader)? {
        guard let streamURL = AuthenticatedStreamURL.wrap(url) else { return nil }
        let asset = AVURLAsset(url: streamURL)
        let loader = AuthorizedResourceLoader(client: client, authorization: authorization, contentType: contentType)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return (asset, loader)
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let streamURL = loadingRequest.request.url, let url = AuthenticatedStreamURL.unwrap(streamURL) else {
            return false
        }
        let key = ObjectIdentifier(loadingRequest)
        let wantsData = loadingRequest.dataRequest != nil
        let handler = HTTPStreamHandler(
            onResponse: { [weak self] head in
                self?.queue.async { self?.describe(head, to: loadingRequest) }
                return wantsData
            },
            onData: { [weak self] data in
                self?.queue.async {
                    guard !loadingRequest.isCancelled, !loadingRequest.isFinished else { return }
                    loadingRequest.dataRequest?.respond(with: data)
                }
            },
            onComplete: { [weak self] error in
                self?.queue.async { self?.finish(loadingRequest, key: key, error: error) }
            }
        )
        do {
            tasks[key] = try client.stream(url, range: Self.byteRange(for: loadingRequest), authorization: authorization, handler: handler)
        } catch {
            loadingRequest.finishLoading(with: Self.nsError(for: .from(error), url: url, authorization: authorization))
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        tasks.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel()
    }

    /// The bytes AVFoundation asked for. A content-information-only request reads two bytes,
    /// which is enough for the server to report the file's full length.
    static func byteRange(for loadingRequest: AVAssetResourceLoadingRequest) -> ByteRange {
        guard let dataRequest = loadingRequest.dataRequest else {
            return ByteRange(lowerBound: 0, upperBound: 1)
        }
        let offset = dataRequest.requestedOffset
        if dataRequest.requestsAllDataToEndOfResource {
            return ByteRange(lowerBound: offset)
        }
        return ByteRange(offset: offset, length: Int64(dataRequest.requestedLength)) ?? ByteRange(lowerBound: offset)
    }

    private func describe(_ head: HTTPResponseHead, to loadingRequest: AVAssetResourceLoadingRequest) {
        guard let info = loadingRequest.contentInformationRequest, !loadingRequest.isCancelled else { return }
        info.contentType = contentType
        info.contentLength = head.totalLength ?? 0
        info.isByteRangeAccessSupported = head.servesByteRanges
    }

    private func finish(_ loadingRequest: AVAssetResourceLoadingRequest, key: ObjectIdentifier, error: HTTPClientError?) {
        tasks[key] = nil
        guard !loadingRequest.isCancelled, !loadingRequest.isFinished else { return }
        if let error, error != .cancelled {
            let url = loadingRequest.request.url.flatMap(AuthenticatedStreamURL.unwrap)
            loadingRequest.finishLoading(with: Self.nsError(for: error, url: url, authorization: authorization))
        } else {
            loadingRequest.finishLoading()
        }
    }

    /// An error AVFoundation passes on, which ``PlaybackErrorText`` turns into a message.
    static func nsError(for error: HTTPClientError, url: URL?, authorization: RequestAuthorization?) -> NSError {
        switch error {
        case .transport(let code, let message):
            return NSError(domain: NSURLErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
        case .status(let head):
            let isGitHub = url.map { GitHubEndpoints.github.hosts.contains($0.host?.lowercased() ?? "") } ?? false
            let message: String
            if isGitHub, let gitHubError = GitHubAPIError.classify(statusCode: head.statusCode, headers: head.headers,
                                                                   hasToken: authorization != nil) {
                message = gitHubError.description
            } else {
                message = statusMessage(head.statusCode)
            }
            return sonusError(code: head.statusCode, message: message)
        case .blockedURL:
            return sonusError(code: -1, message: StreamingErrorMessages.blocked)
        default:
            return sonusError(code: -2, message: error.description)
        }
    }

    private static func sonusError(code: Int, message: String) -> NSError {
        NSError(domain: StreamingErrorMessages.sonusDomain, code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func statusMessage(_ status: Int) -> String {
        switch status {
        case 401, 403:
            return StreamingErrorMessages.denied
        case 404, 410:
            return StreamingErrorMessages.notFound
        default:
            return "The music server answered HTTP \(status)."
        }
    }
}

/// An asset ready for playback or tag reading, with whatever must stay alive alongside it.
struct PreparedAsset {
    let asset: AVURLAsset
    /// Retained here because the asset holds its resource loader weakly.
    let loader: AuthorizedResourceLoader?
    let isLocal: Bool
}

/// Why a song can't be prepared for playback.
struct PlaybackUnavailableError: Error {
    let message: String
}

/// Builds the asset for a song: the local file when it's downloaded or imported, otherwise a
/// stream from its source.
@MainActor
enum PlayerAssetFactory {
    static func asset(for song: Song, sources: SourceStore? = nil) throws -> PreparedAsset {
        let sources = sources ?? .shared
        switch song.playbackRoute {
        case .localFile(let url):
            return PreparedAsset(asset: AVURLAsset(url: url), loader: nil, isLocal: true)
        case .stream(let url):
            return try streamingAsset(for: song, url: url, sources: sources)
        case .unavailable(.missingFile):
            throw PlaybackUnavailableError(message: StreamingErrorMessages.generic)
        case .unavailable(.blockedURL):
            throw PlaybackUnavailableError(message: StreamingErrorMessages.blocked)
        }
    }

    private static func streamingAsset(for song: Song, url: URL, sources: SourceStore) throws -> PreparedAsset {
        let fileExtension = (song.fileName as NSString).pathExtension
        let access = sources.streamingAccess(for: song)
        if access.usesLoader {
            let contentType = AudioFileType.uniformType(forExtension: fileExtension) ?? "public.audio"
            guard let made = AuthorizedResourceLoader.makeAsset(for: url, client: sources.httpClient,
                                                                authorization: access.authorization, contentType: contentType) else {
                throw PlaybackUnavailableError(message: StreamingErrorMessages.blocked)
            }
            return PreparedAsset(asset: made.asset, loader: made.loader, isLocal: false)
        }
        var options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        if let mimeType = AudioFileType.mimeType(forExtension: fileExtension) {
            // Some hosts label audio as application/octet-stream; the file type is more reliable.
            options[AVURLAssetOverrideMIMETypeKey] = mimeType
        }
        return PreparedAsset(asset: AVURLAsset(url: url, options: options), loader: nil, isLocal: false)
    }
}

/// Playback failures in words a person can act on.
enum PlaybackErrorText {
    static func message(for error: (any Error)?) -> String {
        var links: [ErrorLink] = []
        var next = error.map { $0 as NSError }
        while let current = next, links.count < 8 {
            let ownMessage = current.domain == StreamingErrorMessages.sonusDomain ? current.localizedDescription : nil
            links.append(ErrorLink(domain: current.domain, code: current.code, message: ownMessage))
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return StreamingErrorMessages.message(for: links)
    }
}
