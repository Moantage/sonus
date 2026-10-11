import Foundation

/// A `GET /repos/{owner}/{repo}/git/trees/{ref}` response.
public struct GitTree: Decodable, Equatable, Sendable {
    public struct Entry: Decodable, Equatable, Sendable {
        public var path: String
        public var mode: String
        /// `blob`, `tree` or `commit` (a submodule).
        public var type: String
        public var sha: String
        /// Bytes, for blobs.
        public var size: Int64?

        public init(path: String, type: String, sha: String, size: Int64? = nil, mode: String = "100644") {
            self.path = path
            self.mode = mode
            self.type = type
            self.sha = sha
            self.size = size
        }

        public var isBlob: Bool { type == "blob" }
        public var isTree: Bool { type == "tree" }
    }

    public var sha: String
    /// True when GitHub cut the listing short (over 100,000 entries or 7 MB).
    public var truncated: Bool
    public var tree: [Entry]

    enum CodingKeys: String, CodingKey {
        case sha, truncated, tree
    }

    public init(sha: String, truncated: Bool, tree: [Entry]) {
        self.sha = sha
        self.truncated = truncated
        self.tree = tree
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try container.decode(String.self, forKey: .sha)
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        tree = try container.decode([Entry].self, forKey: .tree)
    }
}

/// Builds a library from a repository's files when it has no `sonus.json`.
public enum GitHubTreeLibrary {
    /// Playable audio blobs inside the repository's folder, sorted by path.
    public static func audioEntries(in entries: [GitTree.Entry], repository: GitHubRepository) -> [GitTree.Entry] {
        entries
            .filter { $0.isBlob && repository.contains(path: $0.path) }
            .filter { AudioFileType.isPlayable(fileExtension: ($0.path as NSString).pathExtension) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The track for a blob. Its stable ID is the file's path; the title comes from the file
    /// name until the file's tags are read.
    public static func track(
        for entry: GitTree.Entry,
        repository: GitHubRepository,
        ref: String,
        endpoints: GitHubEndpoints
    ) -> RemoteTrack? {
        guard let url = endpoints.raw(repository, ref: ref, path: entry.path) else { return nil }
        let fileName = (entry.path as NSString).lastPathComponent
        var track = RemoteTrack(
            remoteID: entry.path,
            title: TrackTitleCleaner.title(fromFileName: fileName),
            url: url,
            hasProvisionalMetadata: true
        )
        track.mimeType = AudioFileType.mimeType(forExtension: (fileName as NSString).pathExtension)
        track.size = entry.size
        track.revision = entry.sha
        return track
    }

    /// Where the manifest would be: in the configured folder, or at the root without one.
    public static func manifestPath(for repository: GitHubRepository) -> String {
        repository.path(inFolder: "sonus.json")
    }

    /// Whether a blob is small enough to be a Git LFS pointer rather than real audio.
    public static func mightBeLFSPointer(_ entry: GitTree.Entry) -> Bool {
        guard let size = entry.size else { return false }
        return size > 0 && size <= Int64(LFSPointer.maxSize)
    }
}

/// A Git LFS pointer file, which the raw host serves in place of the real file.
public struct LFSPointer: Equatable, Sendable {
    /// Pointer files are always smaller than this (Git LFS spec).
    public static let maxSize = 1024

    /// Lowercase hex SHA-256 of the real file.
    public let oid: String
    /// Size of the real file in bytes.
    public let size: Int64

    public init?(oid: String, size: Int64) {
        guard oid.count == 64, oid.allSatisfy(\.isHexDigit), size >= 0 else { return nil }
        self.oid = oid.lowercased()
        self.size = size
    }

    /// Parses a pointer file: `version` first, then sorted `key value` lines that include
    /// `oid sha256:<hex>` and `size <bytes>`.
    public static func parse(_ data: Data) -> LFSPointer? {
        guard data.count < maxSize, let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first, isVersionLine(first) else { return nil }

        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: " ", maxSplits: 1)
            guard pair.count == 2 else { return nil }
            fields[String(pair[0])] = String(pair[1])
        }
        guard let oidField = fields["oid"], oidField.hasPrefix("sha256:"),
              let sizeField = fields["size"], let size = Int64(sizeField) else {
            return nil
        }
        return LFSPointer(oid: String(oidField.dropFirst("sha256:".count)), size: size)
    }

    private static func isVersionLine(_ line: String) -> Bool {
        line == "version https://git-lfs.github.com/spec/v1" || line == "version https://hawser.github.com/spec/v1"
    }
}

/// GitHub failures, in words a person can act on.
public enum GitHubAPIError: Error, Equatable, Sendable, CustomStringConvertible {
    /// 401: the token is wrong, revoked or expired.
    case unauthorized
    /// 403 that isn't a rate limit: the token can't read this repository.
    case forbidden
    /// 404: no such repository or branch, or a private one the request can't see.
    case notFound(hasToken: Bool)
    /// Out of requests; `retryAfter` seconds when GitHub says.
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)

    /// Classifies a failed response from the API, raw or media host. Nil for success codes.
    public static func classify(statusCode: Int, headers: [String: String], hasToken: Bool, now: Date = Date()) -> GitHubAPIError? {
        guard !(200..<400).contains(statusCode) else { return nil }
        let lowered = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        if statusCode == 403 || statusCode == 429 {
            if let retryAfter = lowered["retry-after"].flatMap({ TimeInterval($0.trimmingCharacters(in: .whitespaces)) }) {
                return .rateLimited(retryAfter: max(0, retryAfter))
            }
            if lowered["x-ratelimit-remaining"]?.trimmingCharacters(in: .whitespaces) == "0" {
                let reset = lowered["x-ratelimit-reset"].flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
                return .rateLimited(retryAfter: reset.map { max(0, $0 - now.timeIntervalSince1970) })
            }
            if statusCode == 429 {
                return .rateLimited(retryAfter: nil)
            }
        }
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound(hasToken: hasToken)
        default:
            return .http(statusCode)
        }
    }

    public var description: String {
        switch self {
        case .unauthorized:
            return "GitHub rejected the token: it's invalid, revoked or expired. Create a new fine-grained token "
                + "with Contents: read-only access to this repository."
        case .forbidden:
            return "The token can't read this repository. Give it Contents: read-only access to the repository."
        case .notFound(let hasToken):
            return hasToken
                ? "Repository or branch not found, or the token can't see it. Check the name, the branch and the token's repository access."
                : "Repository or branch not found. If the repository is private, add a token that can read it."
        case .rateLimited(let retryAfter):
            guard let retryAfter, retryAfter > 0 else {
                return "GitHub's rate limit was reached. Try again in a few minutes."
            }
            let minutes = Int((retryAfter / 60).rounded(.up))
            return "GitHub's rate limit was reached. Try again in \(minutes) minute\(minutes == 1 ? "" : "s")."
        case .http(let status):
            return "GitHub answered HTTP \(status)."
        }
    }
}
