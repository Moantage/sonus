import Foundation

/// Why a source couldn't be listed.
public enum SourceLoadError: Error, Equatable, Sendable, CustomStringConvertible {
    case blockedURL(URL)
    case http(Int)
    case github(GitHubAPIError)
    case network(String)
    /// The file isn't a Sonus Manifest at all.
    case notAManifest
    /// A Sonus Manifest that breaks the spec's rules. Apps reject these whole.
    case invalidManifest([ManifestIssue])
    case tooLarge
    /// This build can't read this kind of source yet.
    case unsupportedKind(MusicSource.Kind)
    case missingRepository

    public var description: String {
        switch self {
        case .blockedURL(let url):
            "\(url.removingCredentials.absoluteString) isn't allowed: remote servers must use https."
        case .http(let status):
            "The server answered HTTP \(status)."
        case .github(let error):
            error.description
        case .network(let message):
            message
        case .notAManifest:
            "That file isn't a Sonus Manifest (sonus.json)."
        case .invalidManifest(let issues):
            "The manifest breaks the Sonus spec: " + issues.prefix(3).map(\.description).joined(separator: " ")
        case .tooLarge:
            "The listing is too large to read."
        case .unsupportedKind(let kind):
            "\(kind.rawValue) sources aren't supported yet."
        case .missingRepository:
            "This GitHub source has no repository set."
        }
    }

    /// Maps an HTTP failure; GitHub hosts get GitHub's wording.
    static func from(_ error: HTTPClientError, gitHub: Bool, hasToken: Bool) -> SourceLoadError {
        switch error {
        case .blockedURL(let url):
            return .blockedURL(url)
        case .status(let head):
            if gitHub, let classified = GitHubAPIError.classify(statusCode: head.statusCode, headers: head.headers, hasToken: hasToken) {
                return .github(classified)
            }
            return .http(head.statusCode)
        case .tooLarge:
            return .tooLarge
        case .transport(let code, let message):
            return .network(StreamingErrorMessages.transportMessage(code: code) ?? message)
        case .cancelled, .invalidResponse, .rangeNotSatisfiable, .unexpectedRange:
            return .network(error.description)
        }
    }
}

/// Fetches, validates and maps a Sonus Manifest.
public struct ManifestLoader: Sendable {
    public static let maxManifestBytes = 16 * 1024 * 1024

    private let client: StreamingHTTPClient

    public init(client: StreamingHTTPClient) {
        self.client = client
    }

    public func load(from url: URL, authorization: RequestAuthorization? = nil) async throws -> LoadedLibrary {
        let data: Data
        do {
            data = try await client.data(
                url,
                authorization: authorization,
                headers: ["Accept": "application/json"],
                maxBytes: Self.maxManifestBytes
            ).data
        } catch let error as HTTPClientError {
            throw SourceLoadError.from(error, gitHub: false, hasToken: authorization != nil)
        }
        return try Self.library(from: data, manifestURL: url)
    }

    /// Decodes and validates manifest bytes fetched from `manifestURL`.
    public static func library(from data: Data, manifestURL: URL) throws -> LoadedLibrary {
        guard let manifest = try? SonusManifest.decode(from: data) else {
            throw SourceLoadError.notAManifest
        }
        let issues = ManifestValidator.issues(in: manifest, manifestURL: manifestURL)
        guard issues.isEmpty else {
            throw SourceLoadError.invalidManifest(issues)
        }
        return LoadedLibrary(
            name: manifest.library.name,
            tracks: ManifestLibraryMapper.tracks(from: manifest, manifestURL: manifestURL)
        )
    }
}
