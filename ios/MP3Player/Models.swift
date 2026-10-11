import Foundation

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

    // MARK: Cloud / offline (premium)
    // Path of the audio file in cloud storage, if it has been uploaded.
    // NOTE: hosting the audio bytes requires Firebase Storage (Blaze plan) or
    // your own file host. Populated by the upload step; nil until then.
    var remoteStoragePath: String? = nil
    // A direct, downloadable URL for the audio file, if known.
    var remoteURL: URL? = nil

    var displayArtist: String {
        if let artist, artist.isEmpty == false {
            return artist
        }

        return "Local File"
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
