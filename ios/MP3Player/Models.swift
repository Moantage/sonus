import Foundation
import SonusCore

struct Song: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var artist: String?
    var albumName: String?
    var productionHouse: String?
    var fileName: String
    var originalFileName: String
    var duration: TimeInterval
    var importedAt: Date

    // MARK: Cloud / offline
    // Path of the audio file in cloud storage, if it has been uploaded.
    // NOTE: hosting the audio bytes requires Firebase Storage (Blaze plan) or
    // your own file host. Populated by the upload step; nil until then.
    var remoteStoragePath: String? = nil
    // A direct, downloadable URL for the audio file, if known. Songs from a source stream from
    // here until they're downloaded.
    var remoteURL: URL? = nil

    // MARK: Sources (all optional, so older library.json files still decode)

    /// The `MusicSource` this song came from; nil for Files imports and songs synced from older
    /// versions.
    var sourceID: UUID?
    /// The track's stable ID inside its source: a manifest track `id` or a repository path. With
    /// `sourceID` it identifies the song across refreshes.
    var remoteID: String?
    /// Cover art the source publishes for this song.
    var remoteArtworkURL: URL?
    /// Changes when the source's file changes (content hash or Git blob SHA).
    var remoteRevision: String?
    /// Lowercase hex SHA-256 of the audio file, when the source publishes it. Downloads are
    /// checked against it.
    var remoteSHA256: String?
    /// True while the title is a guess from the file name and the file's tags haven't been read.
    var hasProvisionalMetadata: Bool?

    var displayArtist: String {
        if let artist, artist.isEmpty == false {
            return artist
        }

        return remoteURL == nil ? "Local File" : "Unknown Artist"
    }

    /// True for songs listed by a source (manifest, GitHub, …) rather than imported from Files.
    var isFromSource: Bool {
        sourceID != nil
    }

    /// Where the song plays from right now: the file on this device when there is one, so
    /// downloads play offline; otherwise a stream from its source.
    var playbackRoute: PlaybackRoute {
        PlaybackRouter.route(localFile: AppPaths.fileURL(for: self), localFileExists: isDownloadedLocally, remoteURL: remoteURL)
    }

    /// Cover art saved on this device once the song's tags were read, if any.
    var cachedArtworkURL: URL? {
        let url = AppPaths.artworkFileURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// True when the audio file exists on THIS device (playable offline).
    var isDownloadedLocally: Bool {
        FileManager.default.fileExists(atPath: AppPaths.fileURL(for: self).path)
    }

    /// A song that came from the cloud but whose audio isn't on this device yet.
    var isCloudOnly: Bool {
        !isDownloadedLocally && (remoteURL != nil || remoteStoragePath != nil)
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var songIDs: [UUID]
    var createdAt: Date
}

struct LibrarySnapshot: Codable {
    var songs: [Song]
    var playlists: [Playlist]
}

enum RepeatMode: String, CaseIterable, Codable {
    case off
    case one

    var label: String {
        switch self {
        case .off:
            return "Repeat Off"
        case .one:
            return "Repeat On"
        }
    }

    var iconName: String {
        switch self {
        case .off:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }
}

enum AppPaths {
    static var applicationSupportDirectory: URL {
        guard let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        let directory = baseDirectory.appendingPathComponent("MP3Player", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("Error creating application support directory: \(error)")
        }
        return directory
    }

    static var importedSongsDirectory: URL {
        let directory = applicationSupportDirectory.appendingPathComponent("ImportedSongs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("Error creating imported songs directory: \(error)")
        }
        return directory
    }

    static var libraryFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("library.json")
    }

    /// The source list. It holds no secrets: those live in the Keychain.
    static var sourcesFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("sources.json")
    }

    /// Cover art read from songs' tags. Re-creatable, so it lives in Caches.
    static var artworkCacheDirectory: URL {
        cachesSubdirectory("Artwork")
    }

    static func artworkFileURL(for songID: UUID) -> URL {
        artworkCacheDirectory.appendingPathComponent("\(songID.uuidString).jpg")
    }

    /// Resume data for paused downloads that need no credentials.
    static var downloadResumeDirectory: URL {
        cachesSubdirectory("DownloadResume")
    }

    private static func cachesSubdirectory(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("MP3Player", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func fileURL(for song: Song) -> URL {
        // Defense-in-depth: `fileName` can arrive from a cloud-synced snapshot,
        // so strip any path components ("../…") to keep file operations locked
        // inside the ImportedSongs directory.
        let safeName = (song.fileName as NSString).lastPathComponent
        return importedSongsDirectory.appendingPathComponent(safeName)
    }
}

extension TimeInterval {
    var mmssString: String {
        guard isFinite, self > 0 else {
            return "0:00"
        }

        let totalSeconds = Int(self.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}
