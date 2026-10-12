import SwiftUI

/// The three main tabs.
enum AppTab: Hashable, CaseIterable, Identifiable {
    case home
    case search
    case library

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Your Library"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical.fill"
        }
    }
}

/// A list of songs the user can open as its own page and play from.
enum SongCollection: Hashable {
    case allSongs
    case recentlyAdded
    case downloaded
    case playlist(Playlist.ID)

    /// Stable id for "is this what's playing?" checks.
    var contextID: String {
        switch self {
        case .allSongs: return "all"
        case .recentlyAdded: return "recent"
        case .downloaded: return "downloaded"
        case .playlist(let id): return "playlist:\(id.uuidString)"
        }
    }

    func title(in library: LibraryStore) -> String {
        switch self {
        case .allSongs: return "All songs"
        case .recentlyAdded: return "Recently added"
        case .downloaded: return "Downloaded"
        case .playlist(let id): return library.playlist(with: id)?.name ?? "Playlist"
        }
    }

    func songs(in library: LibraryStore) -> [Song] {
        switch self {
        case .allSongs:
            return library.songs
        case .recentlyAdded:
            return Array(library.songs.sorted { $0.importedAt > $1.importedAt }.prefix(50))
        case .downloaded:
            return library.songs.filter(\.isDownloadedLocally)
        case .playlist(let id):
            return library.songs(for: id)
        }
    }

    var playlistID: Playlist.ID? {
        if case .playlist(let id) = self { return id }
        return nil
    }
}

/// Pushed destinations inside a tab's navigation stack.
enum Route: Hashable {
    case profile
    case collection(SongCollection)
}

/// Where a tap-to-play came from: shown as "Playing from …" and used to mark the playing
/// collection's play button.
struct PlayContext: Equatable {
    let id: String
    let name: String
    /// Set when the songs belong to a playlist, so rows can offer "Remove from this playlist".
    var playlistID: Playlist.ID?

    static let library = PlayContext(id: "all", name: "Your Library")
    static let search = PlayContext(id: "search", name: "Search")

    static func collection(_ collection: SongCollection, in library: LibraryStore) -> PlayContext {
        PlayContext(id: collection.contextID, name: collection.title(in: library), playlistID: collection.playlistID)
    }
}

/// UI-only state shared by the app shell: selected tab, per-tab navigation, the Now Playing
/// overlay, and transient UI like toasts. Playback itself stays in `AudioPlayerManager`.
@MainActor
final class ShellState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var paths: [AppTab: [Route]] = [.home: [], .search: [], .library: []]

    @Published var isPlayerExpanded = false
    @Published private(set) var playContext: PlayContext = .library
    /// Backdrop colour taken from the current song's artwork (its average colour), or from its
    /// placeholder. Tints the mini-player and Now Playing.
    @Published private(set) var artworkTint: UIColor = ArtworkPalette.baseColor(for: UUID())

    /// Recomputes `artworkTint` for the current song. The average is computed off the main actor.
    func updateArtworkTint(song: Song?, image: UIImage?) async {
        guard let song else { return }
        guard let image else {
            artworkTint = ArtworkPalette.baseColor(for: song.id)
            return
        }
        let average = await Task.detached(priority: .userInitiated) {
            ArtworkPalette.averageColor(of: image)
        }.value
        artworkTint = average ?? ArtworkPalette.baseColor(for: song.id)
    }

    @Published var isImporterPresented = false
    @Published var isCreatePlaylistPresented = false
    /// A song to add to the playlist that the "name your playlist" flow creates.
    @Published var songForNewPlaylist: Song?

    @Published private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    /// Bumped on every tap-to-play so views can attach haptics to it.
    @Published private(set) var playRequestCount = 0

    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { self.paths[tab] ?? [] },
            set: { self.paths[tab] = $0 }
        )
    }

    func push(_ route: Route) {
        paths[selectedTab, default: []].append(route)
    }

    func popToRoot(_ tab: AppTab) {
        paths[tab] = []
    }

    /// Opens a collection page in Your Library (used after creating a playlist).
    func openInLibrary(_ collection: SongCollection) {
        selectedTab = .library
        paths[.library] = [.collection(collection)]
    }

    /// Tap-to-play: starts `song` in `queue` where the user is. The full player stays closed.
    /// Tapping the song that is already playing from the same list only resumes it.
    func play(_ song: Song, in queue: [Song], context: PlayContext, player: AudioPlayerManager) {
        let sameQueue = player.activeQueue.map(\.id) == queue.map(\.id)
        if player.currentSong?.id == song.id, sameQueue {
            if !player.isPlaying { player.resume() }
        } else {
            player.play(song: song, in: queue)
        }
        playContext = context
        playRequestCount += 1
    }

    /// Plays a whole collection from the top, or toggles it if it's already the one playing.
    func playCollection(_ songs: [Song], context: PlayContext, player: AudioPlayerManager) {
        if isPlaying(context, player: player) || isPaused(context, player: player) {
            player.togglePlayback()
            return
        }
        guard let first = songs.first else { return }
        play(first, in: songs, context: context, player: player)
    }

    func isPlaying(_ context: PlayContext, player: AudioPlayerManager) -> Bool {
        player.isPlaying && playContext.id == context.id && player.currentSong != nil
    }

    private func isPaused(_ context: PlayContext, player: AudioPlayerManager) -> Bool {
        !player.isPlaying && playContext.id == context.id && player.currentSong != nil
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    func startCreatingPlaylist(adding song: Song? = nil) {
        songForNewPlaylist = song
        isCreatePlaylistPresented = true
    }
}

/// Library operations shared by rows, sheets and collection pages.
@MainActor
enum LibraryActions {
    /// Downloads a cloud-only song and points the library at the new local file.
    static func download(_ song: Song, library: LibraryStore, downloads: DownloadManager) {
        Task {
            if let newFile = await downloads.download(song) {
                library.setLocalFileName(newFile, for: song.id)
            }
        }
    }

    /// Only songs that also live on a server can have their local copy removed; a song
    /// imported from Files has no other copy.
    static func canRemoveDownload(_ song: Song) -> Bool {
        song.remoteURL != nil && song.isDownloadedLocally
    }
}

extension User {
    var initials: String {
        "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
    }
}
