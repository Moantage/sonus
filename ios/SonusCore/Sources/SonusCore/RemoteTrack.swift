import Foundation

/// A track as a source describes it, before it becomes a song in the app's library.
public struct RemoteTrack: Equatable, Sendable {
    /// Stable ID inside the source: the manifest track `id` or the file's path in a repository.
    /// Together with the source's ID it identifies the song across refreshes.
    public var remoteID: String
    public var title: String
    public var artist: String?
    public var album: String?
    /// Length in seconds, when the source knows it.
    public var duration: TimeInterval?
    public var url: URL
    public var artworkURL: URL?
    public var mimeType: String?
    /// File size in bytes, when known.
    public var size: Int64?
    /// Lowercase hex SHA-256 of the audio file, when the source publishes it.
    public var sha256: String?
    /// Changes whenever the file's content changes (a content hash or Git blob SHA).
    public var revision: String?
    /// True when the title was guessed from the file name and the file's tags haven't been read.
    public var hasProvisionalMetadata: Bool

    public init(
        remoteID: String,
        title: String,
        url: URL,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        hasProvisionalMetadata: Bool = false
    ) {
        self.remoteID = remoteID
        self.title = title
        self.url = url
        self.artist = artist
        self.album = album
        self.duration = duration
        self.hasProvisionalMetadata = hasProvisionalMetadata
    }
}

/// What a source refresh produced.
public struct LoadedLibrary: Equatable, Sendable {
    /// The library's own name (the manifest's `library.name` or the repository name).
    public var name: String?
    public var tracks: [RemoteTrack]
    /// Problems that didn't stop the refresh, in words a person can act on.
    public var warnings: [String]

    public init(name: String?, tracks: [RemoteTrack], warnings: [String] = []) {
        self.name = name
        self.tracks = tracks
        self.warnings = warnings
    }
}

/// Turns a validated Sonus Manifest into ``RemoteTrack`` values.
public enum ManifestLibraryMapper {
    /// Maps every track whose URL resolves and is allowed by ``NetworkPolicy``.
    /// Run ``ManifestValidator`` first: apps reject manifests that have issues.
    public static func tracks(from manifest: SonusManifest, manifestURL: URL) -> [RemoteTrack] {
        let resolver = ManifestURLResolver(manifest: manifest, manifestURL: manifestURL)
        let artists = Dictionary(manifest.artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let albums = Dictionary(manifest.albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func allowedURL(_ reference: String?) -> URL? {
            guard let reference, let url = resolver.resolve(reference), NetworkPolicy.allows(url) else {
                return nil
            }
            return url
        }

        return manifest.tracks.compactMap { track in
            guard let url = allowedURL(track.url) else { return nil }
            let album = track.albumId.flatMap { albums[$0] }
            let artistName = track.artist
                ?? track.artistId.flatMap { artists[$0]?.name }
                ?? album?.artist
                ?? album?.artistId.flatMap { artists[$0]?.name }

            var remote = RemoteTrack(
                remoteID: track.id,
                title: track.title,
                url: url,
                artist: artistName,
                album: track.album ?? album?.title,
                duration: track.duration
            )
            remote.artworkURL = allowedURL(track.artwork) ?? allowedURL(album?.artwork)
            remote.mimeType = track.mimeType
            remote.size = track.size
            remote.sha256 = track.sha256?.lowercased()
            remote.revision = track.sha256?.lowercased()
            return remote
        }
    }
}

/// Song details the app shows, reduced to plain values so merge rules can be tested.
public struct TrackDetails: Equatable, Sendable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval
    public var isProvisional: Bool

    public init(title: String, artist: String?, album: String?, duration: TimeInterval, isProvisional: Bool) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.isProvisional = isProvisional
    }

    /// The details to keep after a refresh: a source's file-name guess never overwrites tags that
    /// were already read, and a known duration is never replaced by an unknown one.
    public func refreshed(with track: RemoteTrack) -> TrackDetails {
        let incomingDuration = track.duration ?? 0
        let keptDuration = incomingDuration > 0 ? incomingDuration : duration
        if track.hasProvisionalMetadata && !isProvisional {
            return TrackDetails(title: title, artist: artist, album: album, duration: keptDuration, isProvisional: false)
        }
        return TrackDetails(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: keptDuration,
            isProvisional: track.hasProvisionalMetadata
        )
    }

    /// The details after the file's own tags were read. Empty tags keep the current values.
    public func applyingTags(title tagTitle: String?, artist tagArtist: String?, album tagAlbum: String?,
                             duration tagDuration: TimeInterval?) -> TrackDetails {
        func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        let newDuration = tagDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        guard isProvisional else {
            return TrackDetails(title: title, artist: artist, album: album,
                                duration: duration > 0 ? duration : (newDuration ?? 0), isProvisional: false)
        }
        return TrackDetails(
            title: clean(tagTitle) ?? title,
            artist: clean(tagArtist) ?? artist,
            album: clean(tagAlbum) ?? album,
            duration: newDuration ?? duration,
            isProvisional: false
        )
    }
}
