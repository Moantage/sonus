import AVFoundation
import Foundation
import SonusCore

final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published var lastImportError: String?

    private var observers: [NSObjectProtocol] = []

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
        observeEngineEvents()
        startSources()
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

        if song.isDownloadedLocally || song.remoteURL == nil {
            do {
                try FileManager.default.removeItem(at: AppPaths.fileURL(for: song))
            } catch {
                print("Error deleting song file: \(error)")
            }
        }
        ArtworkCache.remove(for: song.id)
        persistLibrary()
    }

    // MARK: - Cloud sync helpers

    /// The current library as a snapshot, for uploading to the cloud. Source credentials never
    /// appear in it: they live only in the Keychain, and any `user:password@` in a URL is removed.
    func currentSnapshot() -> LibrarySnapshot {
        LibrarySnapshot(songs: songs.map(\.withoutURLCredentials), playlists: playlists)
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

// MARK: - Sources

extension LibraryStore {
    /// Songs listed by a source, in library order.
    func songs(fromSource sourceID: UUID) -> [Song] {
        songs.filter { $0.sourceID == sourceID }
    }

    /// Applies a refreshed listing from `source`. Songs are matched by the source's stable track
    /// IDs, so a refresh updates them in place (downloads, playlists and play history survive)
    /// instead of duplicating them. New tracks go to the top; tracks the source dropped are
    /// removed unless they're downloaded.
    @discardableResult
    func applySourceLibrary(_ library: LoadedLibrary, from source: MusicSource) -> SourceMergeSummary {
        let existing: [ExistingSourceSong<Song.ID>] = songs.compactMap { song in
            guard song.sourceID == source.id, let remoteID = song.remoteID else { return nil }
            return ExistingSourceSong(localID: song.id, remoteID: remoteID, isDownloaded: song.isDownloadedLocally)
        }
        let plan = SourceMergePlanner.plan(existing: existing, incoming: library.tracks)

        var updated = songs
        let indexByID = Dictionary(updated.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for update in plan.updates {
            guard let index = indexByID[update.localID] else { continue }
            updated[index] = Self.song(updated[index], refreshedWith: update.track)
        }
        let removed = Set(plan.removals)
        updated.removeAll { removed.contains($0.id) }
        updated.insert(contentsOf: plan.inserts.map { Self.song(from: $0, sourceID: source.id) }, at: 0)

        if updated != songs {
            songs = updated
            removeFromPlaylists(removed)
            removed.forEach(ArtworkCache.remove(for:))
            persistLibrary()
        }
        return SourceMergeSummary(
            added: plan.inserts.count,
            updated: plan.updates.count,
            removed: plan.removals.count,
            keptOffline: plan.keptOffline.count
        )
    }

    /// Removes every song from a source, with its downloaded file and cached artwork.
    func removeSongs(fromSource sourceID: UUID) {
        let doomed = songs.filter { $0.sourceID == sourceID }
        guard !doomed.isEmpty else { return }
        for song in doomed {
            try? FileManager.default.removeItem(at: AppPaths.fileURL(for: song))
            ArtworkCache.remove(for: song.id)
        }
        let ids = Set(doomed.map(\.id))
        songs.removeAll { ids.contains($0.id) }
        removeFromPlaylists(ids)
        persistLibrary()
    }

    /// Uses a song's own tags in place of a title guessed from its file name, and fills in an
    /// unknown duration. Tags never overwrite details the source itself provided.
    func applyReadTags(_ tags: TrackTags, to songID: Song.ID) {
        guard let index = songs.firstIndex(where: { $0.id == songID }) else { return }
        let song = songs[index]
        let current = TrackDetails(
            title: song.title,
            artist: song.artist,
            album: song.albumName,
            duration: song.duration,
            isProvisional: song.hasProvisionalMetadata == true
        )
        let next = current.applyingTags(title: tags.title, artist: tags.artist, album: tags.album, duration: tags.duration)
        guard next != current else { return }
        var updated = song
        updated.title = next.title
        updated.artist = next.artist
        updated.albumName = next.album
        updated.duration = next.duration
        updated.hasProvisionalMetadata = next.isProvisional ? true : nil
        songs[index] = updated
        persistLibrary()
    }

    private func removeFromPlaylists(_ songIDs: Set<Song.ID>) {
        guard !songIDs.isEmpty else { return }
        for index in playlists.indices {
            playlists[index].songIDs.removeAll { songIDs.contains($0) }
        }
    }

    private func observeEngineEvents() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .sonusTrackTagsRead, object: nil, queue: .main) { [weak self] note in
            guard let reading = note.object as? TrackTagsReading else { return }
            self?.applyReadTags(reading.tags, to: reading.songID)
        })
        // A finished download can be read locally: replace a guessed title with the file's tags.
        observers.append(center.addObserver(forName: .sonusDownloadCompleted, object: nil, queue: .main) { [weak self] note in
            guard let self, let songID = note.object as? UUID,
                  let song = self.songs.first(where: { $0.id == songID }), song.hasProvisionalMetadata == true else { return }
            MainActor.assumeIsolated { TrackTagEnricher.shared.enqueue([song], library: self) }
        })
    }

    /// Refreshes stale sources in the background, and in DEBUG builds runs the launch-argument hooks.
    private func startSources() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            #if DEBUG
            await DebugLaunchHooks.run(library: self)
            #endif
            await SourceStore.shared.refreshStaleSources(into: self)
        }
    }

    private static func song(from track: RemoteTrack, sourceID: UUID) -> Song {
        let id = UUID()
        var song = Song(
            id: id,
            title: track.title,
            artist: track.artist,
            albumName: track.album,
            productionHouse: nil,
            fileName: AudioFileType.localFileName(songID: id, url: track.url, mimeType: track.mimeType),
            originalFileName: track.url.lastPathComponent,
            duration: track.duration ?? 0,
            importedAt: Date()
        )
        song.remoteURL = track.url
        song.sourceID = sourceID
        song.remoteID = track.remoteID
        song.remoteArtworkURL = track.artworkURL
        song.remoteRevision = track.revision
        song.remoteSHA256 = track.sha256
        song.hasProvisionalMetadata = track.hasProvisionalMetadata ? true : nil
        return song
    }

    private static func song(_ original: Song, refreshedWith track: RemoteTrack) -> Song {
        var song = original
        let details = TrackDetails(
            title: song.title,
            artist: song.artist,
            album: song.albumName,
            duration: song.duration,
            isProvisional: song.hasProvisionalMetadata == true
        ).refreshed(with: track)
        song.title = details.title
        song.artist = details.artist
        song.albumName = details.album
        song.duration = details.duration
        song.hasProvisionalMetadata = details.isProvisional ? true : nil

        // A changed file makes the downloaded copy stale: drop it so the new version streams.
        if let old = song.remoteRevision, let new = track.revision, old != new, song.isDownloadedLocally {
            try? FileManager.default.removeItem(at: AppPaths.fileURL(for: song))
        }
        song.remoteURL = track.url
        song.remoteArtworkURL = track.artworkURL
        song.remoteRevision = track.revision
        song.remoteSHA256 = track.sha256
        if !song.isDownloadedLocally {
            song.fileName = AudioFileType.localFileName(songID: song.id, url: track.url, mimeType: track.mimeType)
        }
        return song
    }
}
