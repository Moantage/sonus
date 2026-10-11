import Foundation

/// Downloads cloud-only songs to this device for offline playback.
///
/// A song is "downloaded" when its audio file exists locally (see
/// `Song.isDownloadedLocally`). Locally-imported songs are already offline.
/// For songs that came from another device via sync, this downloads the audio
/// from `song.remoteURL` into the app's ImportedSongs folder.
///
/// NOTE (Spark plan): populating `remoteURL` — i.e. actually HOSTING the audio
/// so other devices can fetch it — requires Firebase Storage (Blaze) or your own
/// file host. This manager is ready for that: once songs carry a real
/// `remoteURL`, downloads work with no further changes.
@MainActor
final class DownloadManager: ObservableObject {

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(String)
    }

    @Published private(set) var states: [Song.ID: State] = [:]

    private var tasks: [Song.ID: Task<Void, Never>] = [:]

    /// Current state for a song, derived from disk if not tracked in memory.
    func state(for song: Song) -> State {
        if let tracked = states[song.id] { return tracked }
        return song.isDownloadedLocally ? .downloaded : .notDownloaded
    }

    func isDownloaded(_ song: Song) -> Bool {
        if case .downloaded = state(for: song) { return true }
        return song.isDownloadedLocally
    }

    /// Downloads a cloud-only song's audio to local storage.
    /// - Returns: the local file name to persist on the Song, or nil on failure.
    @discardableResult
    func download(_ song: Song) async -> String? {
        guard !song.isDownloadedLocally else {
            states[song.id] = .downloaded
            return song.fileName
        }
        guard let remoteURL = song.remoteURL else {
            states[song.id] = .failed("This track isn't hosted in the cloud yet.")
            return nil
        }
        // Only fetch over HTTPS. `remoteURL` comes from a synced snapshot, so
        // never allow file://, http://, or other schemes.
        guard remoteURL.scheme?.lowercased() == "https" else {
            states[song.id] = .failed("This track's download link isn't secure.")
            return nil
        }

        states[song.id] = .downloading(progress: 0)
        let destination = AppPaths.fileURL(for: song)

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                states[song.id] = .failed("Download failed (\(http.statusCode)).")
                return nil
            }
            // Move into place (overwrite any partial).
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            states[song.id] = .downloaded
            return destination.lastPathComponent
        } catch {
            states[song.id] = .failed("Download failed. Check your connection.")
            return nil
        }
    }

    /// Removes a downloaded file to free space (keeps the library entry so it
    /// can be re-downloaded later).
    func removeDownload(_ song: Song) {
        try? FileManager.default.removeItem(at: AppPaths.fileURL(for: song))
        states[song.id] = song.remoteURL != nil ? .notDownloaded : .downloaded
    }

    func cancel(_ song: Song) {
        tasks[song.id]?.cancel()
        tasks[song.id] = nil
        if case .downloading = states[song.id] { states[song.id] = .notDownloaded }
    }
}
