import Foundation

/// A place Sonus reads music from: a Sonus Manifest, a GitHub repository or (later) a server.
///
/// Sources hold no secrets. A source that needs one names a Keychain item through
/// ``credentialKey``; the app stores the token there and nowhere else.
public struct MusicSource: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// A static `sonus.json` (Sonus Manifest v1) on any web host.
        case manifest
        /// A GitHub repository, listed with its `sonus.json` or straight from the Git tree.
        case github
        /// Reserved: the Sonus Server API (`spec/openapi.yaml`). Not implemented yet.
        case sonusServer
        /// Reserved: OpenSubsonic servers such as Navidrome. Not implemented yet.
        case openSubsonic

        /// Whether this build can list and play this kind of source.
        public var isSupported: Bool {
            switch self {
            case .manifest, .github:
                true
            case .sonusServer, .openSubsonic:
                false
            }
        }
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// The manifest URL, the repository's web URL, or the server's base URL.
    public var url: URL
    /// Set for ``Kind/github`` sources.
    public var github: GitHubRepository?
    /// Keychain account name of this source's secret, or nil when it needs none.
    public var credentialKey: String?
    public var addedAt: Date
    public var lastRefreshedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        url: URL,
        github: GitHubRepository? = nil,
        credentialKey: String? = nil,
        addedAt: Date = Date(),
        lastRefreshedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.url = url
        self.github = github
        self.credentialKey = credentialKey
        self.addedAt = addedAt
        self.lastRefreshedAt = lastRefreshedAt
    }

    /// The Keychain account name used for a source's secret.
    public static func defaultCredentialKey(for id: UUID) -> String {
        "source.\(id.uuidString).credential"
    }

    /// A manifest source for `url`.
    public static func manifest(url: URL, name: String? = nil) -> MusicSource {
        MusicSource(name: name ?? url.host ?? "Music library", kind: .manifest, url: url)
    }

    /// A GitHub source for `repository`.
    public static func github(_ repository: GitHubRepository, name: String? = nil) -> MusicSource {
        MusicSource(name: name ?? repository.name, kind: .github, url: repository.webURL, github: repository)
    }

    /// True when `other` points at the same library, so adding it again should refresh this one.
    public func isSameLibrary(as other: MusicSource) -> Bool {
        guard kind == other.kind else { return false }
        if kind == .github, let mine = github, let theirs = other.github {
            return mine.isSameLocation(as: theirs)
        }
        return url.absoluteString == other.url.absoluteString
    }
}

/// The on-disk form of the source list (`sources.json`).
///
/// Decoding skips entries this build can't read, e.g. a kind added by a newer version, so one
/// unknown source never hides the others.
public struct SourceList: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var sources: [MusicSource]

    public init(sources: [MusicSource]) {
        version = Self.currentVersion
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case version, sources
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        let entries = try container.decodeIfPresent([Lenient<MusicSource>].self, forKey: .sources) ?? []
        sources = entries.compactMap(\.value)
    }

    public static func decode(from data: Data) throws -> SourceList {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SourceList.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

/// Decodes a value, or nil if it doesn't decode, without failing the surrounding container.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
