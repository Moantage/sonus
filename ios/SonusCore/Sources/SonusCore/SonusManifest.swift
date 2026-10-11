import Foundation

/// A Sonus Manifest (`sonus.json`) as defined by `spec/schemas/manifest.schema.json`.
///
/// Decoding is lenient in the ways the spec requires: unknown fields are ignored and the
/// optional collections default to empty. Rules the JSON Schema can't express (unique IDs,
/// resolvable references, secure URLs) are checked by ``ManifestValidator``.
public struct SonusManifest: Codable, Equatable, Sendable {
    public var schema: String?
    public var sonus: String
    public var library: Library
    public var baseURL: URL?
    public var artists: [Artist]
    public var albums: [Album]
    public var tracks: [Track]
    public var playlists: [Playlist]

    public init(
        sonus: String = "1.0",
        library: Library,
        baseURL: URL? = nil,
        artists: [Artist] = [],
        albums: [Album] = [],
        tracks: [Track] = [],
        playlists: [Playlist] = []
    ) {
        self.sonus = sonus
        self.library = library
        self.baseURL = baseURL
        self.artists = artists
        self.albums = albums
        self.tracks = tracks
        self.playlists = playlists
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case sonus, library
        case baseURL = "baseUrl"
        case artists, albums, tracks, playlists
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decodeIfPresent(String.self, forKey: .schema)
        sonus = try container.decode(String.self, forKey: .sonus)
        library = try container.decode(Library.self, forKey: .library)
        baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
        artists = try container.decodeIfPresent([Artist].self, forKey: .artists) ?? []
        albums = try container.decodeIfPresent([Album].self, forKey: .albums) ?? []
        tracks = try container.decode([Track].self, forKey: .tracks)
        playlists = try container.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
    }

    /// Decodes a manifest, accepting RFC 3339 timestamps with or without fractional seconds.
    public static func decode(from data: Data) throws -> SonusManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = try? Date(value, strategy: .iso8601) {
                return date
            }
            if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an RFC 3339 date-time, got \"\(value)\""
            )
        }
        return try decoder.decode(SonusManifest.self, from: data)
    }
}

public extension SonusManifest {
    struct Library: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var description: String?
        public var updatedAt: Date?

        public init(id: String, name: String, description: String? = nil, updatedAt: Date? = nil) {
            self.id = id
            self.name = name
            self.description = description
            self.updatedAt = updatedAt
        }
    }

    struct Artist: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var artwork: String?

        public init(id: String, name: String, artwork: String? = nil) {
            self.id = id
            self.name = name
            self.artwork = artwork
        }
    }

    struct Album: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var artist: String?
        public var artistId: String?
        public var year: Int?
        public var genre: String?
        public var artwork: String?

        public init(id: String, title: String, artist: String? = nil, artistId: String? = nil) {
            self.id = id
            self.title = title
            self.artist = artist
            self.artistId = artistId
        }
    }

    struct Track: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        /// Absolute URL or a reference relative to the manifest's base. Resolve with
        /// ``ManifestURLResolver``.
        public var url: String
        public var artist: String?
        public var artistId: String?
        public var album: String?
        public var albumId: String?
        public var trackNumber: Int?
        public var discNumber: Int?
        /// Length in seconds.
        public var duration: Double?
        public var mimeType: String?
        /// File size in bytes.
        public var size: Int64?
        /// Average bitrate in kbit/s.
        public var bitrate: Int?
        public var sha256: String?
        public var genre: String?
        public var year: Int?
        public var artwork: String?
        public var addedAt: Date?

        public init(id: String, title: String, url: String) {
            self.id = id
            self.title = title
            self.url = url
        }
    }

    struct Playlist: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var description: String?
        public var artwork: String?
        /// Track IDs in play order.
        public var trackIds: [String]

        public init(id: String, name: String, trackIds: [String]) {
            self.id = id
            self.name = name
            self.trackIds = trackIds
        }
    }
}
