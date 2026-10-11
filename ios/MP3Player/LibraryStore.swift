import AVFoundation
import Foundation

final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published var lastImportError: String?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        loadLibrary()
    }

    func songs(for playlistID: Playlist.ID?) -> [Song] {
        guard let playlistID else {
            return songs
        }

        guard let playlist = playlists.first(where: { $0.id == playlistID }) else {
            return songs
        }

        let order = Dictionary(uniqueKeysWithValues: playlist.songIDs.enumerated().map { ($0.element, $0.offset) })
        return songs
            .filter { order[$0.id] != nil }
            .sorted {
                (order[$0.id] ?? .max) < (order[$1.id] ?? .max)
            }
    }

    func playlist(with id: Playlist.ID?) -> Playlist? {
        guard let id else {
            return nil
        }

        return playlists.first(where: { $0.id == id })
    }

    func importFiles(from sourceURLs: [URL]) {
        guard sourceURLs.isEmpty == false else {
            return
        }

        do {
            var importedSongs: [Song] = []

            for sourceURL in sourceURLs {
                let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccessSecurityScope {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let destinationURL = uniqueDestinationURL(for: sourceURL)
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                let metadata = extractMetadata(from: destinationURL, fallbackName: sourceURL.deletingPathExtension().lastPathComponent)

                let song = Song(
                    id: UUID(),
                    title: metadata.title,
                    artist: metadata.artist,
                    albumName: metadata.albumName,
                    productionHouse: metadata.productionHouse,
                    fileName: destinationURL.lastPathComponent,
                    originalFileName: sourceURL.lastPathComponent,
                    duration: metadata.duration,
                    importedAt: Date()
                )

                importedSongs.append(song)
            }

            songs.insert(contentsOf: importedSongs.reversed(), at: 0)
            persistLibrary()
            lastImportError = nil
        } catch {
            lastImportError = error.localizedDescription
        }
    }

    func createPlaylist(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard name.isEmpty == false else {
            return
        }

        playlists.insert(
            Playlist(id: UUID(), name: name, songIDs: [], createdAt: Date()),
            at: 0
        )
        persistLibrary()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        persistLibrary()
    }

    func addSong(_ song: Song, to playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else {
            return
        }

        if playlists[index].songIDs.contains(song.id) == false {
            playlists[index].songIDs.append(song.id)
            persistLibrary()
        }
    }

    func removeSong(_ song: Song, from playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else {
            return
        }

        playlists[index].songIDs.removeAll { $0 == song.id }
        persistLibrary()
    }

    func deleteSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }

        for index in playlists.indices {
            playlists[index].songIDs.removeAll { $0 == song.id }
        }

        do {
            try FileManager.default.removeItem(at: AppPaths.fileURL(for: song))
        } catch {
            print("Error deleting song file: \(error)")
        }
        persistLibrary()
    }

    // MARK: - Cloud sync helpers

    /// The current library as a snapshot, for uploading to the cloud.
    func currentSnapshot() -> LibrarySnapshot {
        LibrarySnapshot(songs: songs, playlists: playlists)
    }

    /// Merges a cloud snapshot into the local library (adds entries not already
    /// present, by id). Songs whose audio isn't on this device appear as
    /// cloud-only until downloaded.
    func mergeRemoteSnapshot(_ snapshot: LibrarySnapshot) {
        var existingSongs = Set(songs.map(\.id))
        var changed = false

        for remote in snapshot.songs where existingSongs.contains(remote.id) == false {
            songs.append(remote)
            existingSongs.insert(remote.id)
            changed = true
        }

        var existingPlaylists = Set(playlists.map(\.id))
        for remotePlaylist in snapshot.playlists where existingPlaylists.contains(remotePlaylist.id) == false {
            playlists.append(remotePlaylist)
            existingPlaylists.insert(remotePlaylist.id)
            changed = true
        }

        if changed { persistLibrary() }
    }

    /// Points a song at a newly downloaded local file.
    func setLocalFileName(_ fileName: String, for songID: Song.ID) {
        guard let index = songs.firstIndex(where: { $0.id == songID }) else { return }
        songs[index].fileName = fileName
        persistLibrary()
    }

    private func loadLibrary() {
        let fileURL = AppPaths.libraryFileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(LibrarySnapshot.self, from: data)
            songs = snapshot.songs
            playlists = snapshot.playlists
        } catch {
            lastImportError = "Unable to load your saved music library."
        }
    }

    private func persistLibrary() {
        let snapshot = LibrarySnapshot(songs: songs, playlists: playlists)

        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: AppPaths.libraryFileURL, options: [.atomic, .completeFileProtection])
        } catch {
            lastImportError = "Unable to save your music library."
            print("Error persisting library: \(error)")
        }
    }

    private func uniqueDestinationURL(for sourceURL: URL) -> URL {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension.lowercased()
        let fileName = UUID().uuidString + "." + fileExtension
        return AppPaths.importedSongsDirectory.appendingPathComponent(fileName)
    }

    private func extractMetadata(from fileURL: URL, fallbackName: String) -> (title: String, artist: String?, albumName: String?, productionHouse: String?, duration: TimeInterval) {
        let asset = AVURLAsset(url: fileURL)
        let commonMetadata = asset.commonMetadata

        let title = AVMetadataItem.metadataItems(from: commonMetadata, filteredByIdentifier: .commonIdentifierTitle)
            .first?
            .stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = AVMetadataItem.metadataItems(from: commonMetadata, filteredByIdentifier: .commonIdentifierArtist)
            .first?
            .stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let albumName = AVMetadataItem.metadataItems(from: commonMetadata, filteredByIdentifier: .commonIdentifierAlbumName)
            .first?
            .stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let productionHouse = AVMetadataItem.metadataItems(from: commonMetadata, filteredByIdentifier: .commonIdentifierPublisher)
            .first?
            .stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawDuration = CMTimeGetSeconds(asset.duration)
        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 0

        return (
            title: (title?.isEmpty == false ? title! : fallbackName),
            artist: artist?.isEmpty == false ? artist : nil,
            albumName: albumName?.isEmpty == false ? albumName : nil,
            productionHouse: productionHouse?.isEmpty == false ? productionHouse : nil,
            duration: duration
        )
    }
}
