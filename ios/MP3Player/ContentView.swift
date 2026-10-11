import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var navigationPath = NavigationPath()
    @State private var isImporterPresented = false
    @State private var isCreatePlaylistPresented = false
    @State private var newPlaylistName = ""
    @State private var selectedPlaylistID: Playlist.ID?
    @State private var searchQuery = ""

    private var visibleSongs: [Song] {
        libraryStore.songs(for: selectedPlaylistID)
    }

    private var selectedPlaylist: Playlist? {
        libraryStore.playlist(with: selectedPlaylistID)
    }

    private var filteredSongs: [Song] {
        rankedSearchResults(for: searchQuery, in: visibleSongs)
    }

    private var highlightedSong: Song? {
        let highlightedID = player.currentSong?.id ?? player.lastPlayedSongID
        guard let highlightedID else {
            return nil
        }

        return libraryStore.songs.first(where: { $0.id == highlightedID })
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    headerSection

                    if libraryStore.playlists.isEmpty == false {
                        playlistStrip
                    }

                    songsSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            // Gradient as a bleeding background (instead of a ZStack layer) so the
            // ScrollView remains the primary content and correctly respects safe
            // areas — including the top ad banner's inset, which otherwise
            // overlapped the title and Import button.
            .background(Theme.backgroundBase.ignoresSafeArea())
            .foregroundStyle(Theme.textPrimary)
            .preferredColorScheme(.light)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Song.ID.self) { _ in
                PlayerDetailView()
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                libraryStore.importFiles(from: urls)
            case .failure(let error):
                libraryStore.lastImportError = error.localizedDescription
            }
        }
        .alert("Create Playlist", isPresented: $isCreatePlaylistPresented) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") {
                libraryStore.createPlaylist(named: newPlaylistName)
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
        } message: {
            Text("Create a playlist for imported songs.")
        }
        .alert("Library Error", isPresented: libraryErrorBinding) {
            Button("OK", role: .cancel) {
                libraryStore.lastImportError = nil
            }
        } message: {
            Text(libraryStore.lastImportError ?? "Something went wrong.")
        }
        .alert("Playback Error", isPresented: playbackErrorBinding) {
            Button("OK", role: .cancel) {
                player.lastPlaybackError = nil
            }
        } message: {
            Text(player.lastPlaybackError ?? "This track could not be played.")
        }
        .onChange(of: libraryStore.playlists) { _, playlists in
            if let selectedPlaylistID, playlists.contains(where: { $0.id == selectedPlaylistID }) == false {
                self.selectedPlaylistID = nil
            }
        }
        .task {
            player.syncLibrary(with: libraryStore.songs)
        }
        .onChange(of: libraryStore.songs) { _, songs in
            player.syncLibrary(with: songs)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("SONUS · SIDE A")
                            .font(Theme.mono(10, weight: .regular))
                            .tracking(1.5)
                            .foregroundStyle(Theme.accent)
                        WaveformMark(size: 16)
                    }

                    Text("Library")
                        .font(Theme.serif(44))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 2)

                    Text("Your imported Files library, ready for playback and lock-screen controls.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(minWidth: 128)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())

                    Menu {
                        Button("Create Playlist", systemImage: "text.badge.plus") {
                            isCreatePlaylistPresented = true
                        }

                        if let selectedPlaylist {
                            Button("Delete \(selectedPlaylist.name)", systemImage: "trash", role: .destructive) {
                                libraryStore.deletePlaylist(selectedPlaylist)
                                selectedPlaylistID = nil
                            }
                        }
                    } label: {
                        Label("Playlists", systemImage: "music.note.list")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(minWidth: 128)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
            }

            if let highlightedSong {
                Button {
                    openPlayer(for: highlightedSong)
                } label: {
                    HStack(spacing: 14) {
                        Image("PlayerArtwork")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .padding(10)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 2, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text((player.currentSong?.id == highlightedSong.id ? "Current Selection" : "Last Played").uppercased())
                                .font(Theme.mono(10, weight: .regular))
                                .tracking(1.2)
                                .foregroundStyle(Theme.accent)

                            Text(highlightedSong.title)
                                .font(Theme.serif(19))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)

                            Text(highlightedSong.displayArtist)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSubtle)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(16)
                    .emberCard(cornerRadius: 2, fill: Theme.surfaceRaised)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 20)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private var playlistStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                PlaylistChip(
                    title: "All Songs",
                    subtitle: "\(libraryStore.songs.count)",
                    isSelected: selectedPlaylistID == nil
                ) {
                    selectedPlaylistID = nil
                }

                ForEach(libraryStore.playlists) { playlist in
                    PlaylistChip(
                        title: playlist.name,
                        subtitle: "\(playlist.songIDs.count)",
                        isSelected: selectedPlaylistID == playlist.id
                    ) {
                        selectedPlaylistID = playlist.id
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var songsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text((selectedPlaylist == nil ? "IN ROTATION" : "PLAYLIST").uppercased())
                        .font(Theme.mono(9, weight: .regular))
                        .tracking(1.5)
                        .foregroundStyle(Theme.accent)

                    Text(selectedPlaylist?.name ?? "Songs")
                        .font(Theme.serif(28))
                        .foregroundStyle(Theme.textPrimary)
                }

                Spacer(minLength: 0)

                Text("\(filteredSongs.count)")
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }

            searchField

            if filteredSongs.isEmpty {
                if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyState
                } else {
                    searchEmptyState
                }
            } else if visibleSongs.isEmpty {
                emptyState
            } else {
                songList
            }
        }
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredSongs) { song in
                SongListRow(
                    song: song,
                    isHighlighted: isHighlighted(song),
                    isCurrent: player.currentSong?.id == song.id,
                    isPlayingThis: player.isPlaying && player.currentSong?.id == song.id,
                    playlists: libraryStore.playlists,
                    activePlaylist: selectedPlaylist,
                    playAction: {
                        openPlayer(for: song)
                    },
                    togglePlaybackAction: {
                        togglePlayback(for: song)
                    },
                    addToPlaylistAction: { playlist in
                        libraryStore.addSong(song, to: playlist)
                    },
                    removeFromPlaylistAction: {
                        if let selectedPlaylist {
                            libraryStore.removeSong(song, from: selectedPlaylist)
                        }
                    },
                    deleteAction: {
                        libraryStore.deleteSong(song)
                    },
                    downloadState: downloadManager.state(for: song),
                    downloadAction: song.isCloudOnly ? {
                        Task {
                            if let newFile = await downloadManager.download(song) {
                                libraryStore.setLocalFileName(newFile, for: song.id)
                            }
                        }
                    } : nil
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No songs imported yet.")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("Tap Import to bring MP3 files in from the Files app. Once a song is imported, it stays inside the app for playback and lock-screen control.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSubtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .emberCard(cornerRadius: 2)
    }

    private var searchEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No matching songs.")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("Try another song name, album, or production house.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSubtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .emberCard(cornerRadius: 2)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.accent)

            TextField("Search by song, album, or production house", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.textPrimary)

            if searchQuery.isEmpty == false {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSubtle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .emberCard(cornerRadius: 2)
    }

    private func rankedSearchResults(for rawQuery: String, in songs: [Song]) -> [Song] {
        let normalizedQuery = normalizeSearchText(rawQuery)
        guard normalizedQuery.isEmpty == false else {
            return songs
        }

        let terms = normalizedQuery.split(separator: " ").map(String.init)
        guard terms.isEmpty == false else {
            return songs
        }

        let scored = songs.compactMap { song -> (song: Song, score: Int)? in
            let score = searchScore(for: song, terms: terms)
            return score > 0 ? (song, score) : nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.song.title.localizedCaseInsensitiveCompare(rhs.song.title) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .map(\.song)
    }

    private func searchScore(for song: Song, terms: [String]) -> Int {
        let title = normalizeSearchText(song.title)
        let album = normalizeSearchText(song.albumName ?? "")
        let productionHouse = normalizeSearchText(song.productionHouse ?? "")
        let artist = normalizeSearchText(song.artist ?? "")
        let fullText = [title, album, productionHouse, artist].joined(separator: " ")
        var score = 0

        for term in terms {
            var termScore = 0

            if title == term {
                termScore = max(termScore, 140)
            }
            if title.hasPrefix(term) {
                termScore = max(termScore, 100)
            }
            if title.localizedStandardContains(term) {
                termScore = max(termScore, 78)
            }
            if album.hasPrefix(term) {
                termScore = max(termScore, 66)
            }
            if album.localizedStandardContains(term) {
                termScore = max(termScore, 56)
            }
            if productionHouse.hasPrefix(term) {
                termScore = max(termScore, 62)
            }
            if productionHouse.localizedStandardContains(term) {
                termScore = max(termScore, 52)
            }
            if artist.localizedStandardContains(term) {
                termScore = max(termScore, 48)
            }
            if fullText.localizedStandardContains(term) {
                termScore = max(termScore, 38)
            }

            if termScore == 0 {
                return 0
            }

            score += termScore
        }

        return score
    }

    private func normalizeSearchText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openPlayer(for song: Song) {
        let queue = queue(for: song)
        let queuedSongIDs = player.activeQueue.map(\.id)
        let targetSongIDs = queue.map(\.id)

        if player.currentSong?.id != song.id || queuedSongIDs != targetSongIDs {
            player.play(song: song, in: queue)
        }

        navigationPath = NavigationPath()
        navigationPath.append(song.id)
    }

    /// Toggles playback for a song directly from the list, without opening the
    /// full player. If it's already the current track, play/pause; otherwise
    /// start it playing in place.
    private func togglePlayback(for song: Song) {
        if player.currentSong?.id == song.id {
            player.togglePlayback()
        } else {
            player.play(song: song, in: queue(for: song))
        }
    }

    private func queue(for song: Song) -> [Song] {
        if visibleSongs.contains(song) {
            return visibleSongs
        }

        if libraryStore.songs.contains(song) {
            return libraryStore.songs
        }

        return [song]
    }

    private func isHighlighted(_ song: Song) -> Bool {
        song.id == player.currentSong?.id || song.id == player.lastPlayedSongID
    }

    private var libraryErrorBinding: Binding<Bool> {
        Binding(
            get: { libraryStore.lastImportError != nil },
            set: { newValue in
                if newValue == false {
                    libraryStore.lastImportError = nil
                }
            }
        )
    }

    private var playbackErrorBinding: Binding<Bool> {
        Binding(
            get: { player.lastPlaybackError != nil },
            set: { newValue in
                if newValue == false {
                    player.lastPlaybackError = nil
                }
            }
        )
    }
}

private struct PlayerDetailView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAdvancedControls = false
    @State private var showPaywall = false

    private var isPremium: Bool {
        store.isPremium || authManager.currentUser?.isPremium == true
    }

    var body: some View {
        ZStack {
            Theme.playerBackground

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 6)

                Spacer(minLength: 0)

                VStack(spacing: 26) {
                    artworkView

                    VStack(spacing: 10) {
                        Text("LOSSLESS · HI-FI")
                            .font(Theme.mono(10, weight: .regular))
                            .tracking(1.5)
                            .foregroundStyle(Theme.accent)

                        Text(player.currentSong?.title ?? "No song selected")
                            .font(Theme.serif(34))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)

                        Text(player.currentSong?.displayArtist ?? "Choose a song from your library")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSubtle)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 24)

                    WaveformScrubber(
                        currentTime: player.currentTime,
                        duration: max(player.duration, 1),
                        onScrub: { player.seek(to: $0) }
                    )
                    .padding(.horizontal, 26)
                }

                Spacer(minLength: 0)

                capsuleRow
                    .padding(.bottom, 18)

                transport
                    .padding(.bottom, 58)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .sheet(isPresented: $showAdvancedControls) {
            AdvancedControlsSheet().environmentObject(player)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("NOW PLAYING")
                .font(Theme.mono(10, weight: .regular))
                .tracking(1.5)
                .foregroundStyle(Theme.textMuted)

            Spacer()

            Image(systemName: "list.bullet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textSubtle)
                .frame(width: 40, height: 40)
        }
    }

    private var capsuleRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: player.repeatMode.iconName)
                    .font(.footnote.weight(.bold))
                Text(player.repeatMode.label)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Theme.textPrimary.opacity(0.88))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.surfaceRaised, in: Capsule())

            // Premium: advanced audio controls
            Button {
                if isPremium { showAdvancedControls = true } else { showPaywall = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPremium ? "slider.horizontal.3" : "lock.fill")
                        .font(.footnote.weight(.bold))
                    Text(player.playbackSpeed == 1.0 ? "Controls" : speedLabel(player.playbackSpeed))
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.textPrimary.opacity(0.88))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.surfaceRaised, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var transport: some View {
        HStack(spacing: 24) {
            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .background(
                        player.repeatMode == .one ? Theme.accent : Theme.surface,
                        in: Circle()
                    )
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: player.repeatMode == .one ? 0 : 1))
                    .foregroundStyle(player.repeatMode == .one ? Theme.accentInk : Theme.textPrimary)
            }
            .buttonStyle(.plain)

            PlayerControlButton(systemImage: "backward.fill", size: 54) {
                player.playPrevious()
            }

            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 72, height: 72)
                    .background(Theme.ink, in: Circle())
                    .foregroundStyle(Theme.accentInk)
                    .shadow(color: Theme.ink.opacity(0.3), radius: 16, y: 8)
            }
            .buttonStyle(.plain)

            PlayerControlButton(systemImage: "forward.fill", size: 54) {
                player.playNext()
            }
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        speed == 1.0 ? "1×" : String(format: "%g×", speed)
    }

    @ViewBuilder
    private var artworkView: some View {
        Group {
            if let artworkImage = player.artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.artworkGradient
                    Image("PlayerArtwork")
                        .resizable()
                        .scaledToFit()
                        .padding(52)
                }
            }
        }
        .frame(width: 256, height: 256)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.35), radius: 40, y: 24)
    }
}

/// Amber waveform scrubber that echoes the Sonus logo. Tappable / draggable to seek.
private struct WaveformScrubber: View {
    let currentTime: Double
    let duration: Double
    let onScrub: (Double) -> Void

    private let barCount = 40
    private let barWidth: CGFloat = 3
    private let gap: CGFloat = 3

    // Deterministic pseudo-random heights (7–34pt) so bars stay stable across redraws.
    private var heights: [CGFloat] {
        (0..<barCount).map { i in
            let seed = sin(Double(i) * 12.9898) * 43758.5453
            let frac = seed - floor(seed)
            return 7 + CGFloat(frac) * 27
        }
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let playedIndex = Int((Double(barCount) * progress).rounded())
                HStack(alignment: .center, spacing: gap) {
                    ForEach(0..<barCount, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(color(for: i, playhead: playedIndex))
                            .frame(width: barWidth, height: heights[i] + (i == playedIndex ? 4 : 0))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            onScrub(ratio * duration)
                        }
                )
            }
            .frame(height: 40)

            HStack {
                Text(currentTime.mmssString)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("-" + max(duration - currentTime, 0).mmssString)
                    .foregroundStyle(Theme.textSubtle)
            }
            .font(.caption.monospacedDigit())
        }
    }

    private func color(for index: Int, playhead: Int) -> Color {
        if index == playhead { return Theme.accentLight }
        if index < playhead { return Theme.accent }
        return Theme.textPrimary.opacity(0.16)
    }
}

private struct SongListRow: View {
    let song: Song
    let isHighlighted: Bool
    let isCurrent: Bool
    let isPlayingThis: Bool
    let playlists: [Playlist]
    let activePlaylist: Playlist?
    let playAction: () -> Void
    let togglePlaybackAction: () -> Void
    let addToPlaylistAction: (Playlist) -> Void
    let removeFromPlaylistAction: () -> Void
    let deleteAction: () -> Void
    var downloadState: DownloadManager.State = .downloaded
    var downloadAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let downloadAction {
                downloadAccessory(action: downloadAction)
            }

            // Picture card doubles as a play/pause control — toggles playback
            // in place without opening the full player.
            Button(action: togglePlaybackAction) {
                Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(
                        isCurrent ? Theme.ink : Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 2, style: .continuous)
                    )
                    .foregroundStyle(isCurrent ? Theme.accentInk : Theme.textPrimary)
                    .contentShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .buttonStyle(.plain)

            // Tapping the track details opens the full player.
            Button(action: playAction) {
                VStack(alignment: .leading, spacing: 5) {
                    MarqueeText(
                        text: song.title,
                        font: Theme.serif(18, weight: .regular),
                        uiFont: .systemFont(ofSize: 18, weight: .semibold),
                        color: Theme.textPrimary
                    )

                    HStack(spacing: 10) {
                        Text(song.displayArtist)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSubtle)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(song.duration.mmssString)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSubtle)
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                if playlists.isEmpty {
                    Button("Create Playlist First") { }
                        .disabled(true)
                } else {
                    Menu("Add to Playlist") {
                        ForEach(playlists) { playlist in
                            Button(playlist.name) {
                                addToPlaylistAction(playlist)
                            }
                        }
                    }
                }

                if activePlaylist != nil {
                    Button("Remove from Playlist", systemImage: "minus.circle") {
                        removeFromPlaylistAction()
                    }
                }

                Button("Delete Track", systemImage: "trash", role: .destructive) {
                    deleteAction()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.headline.weight(.bold))
                    .frame(width: 38, height: 38)
                    .background(Theme.surfaceRaised, in: Circle())
            }
            .tint(Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .background(
            isHighlighted ? Theme.surfaceRaised : Color.clear,
            in: RoundedRectangle(cornerRadius: 2, style: .continuous)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private func downloadAccessory(action: @escaping () -> Void) -> some View {
        switch downloadState {
        case .downloading:
            ProgressView()
                .tint(Theme.accent)
                .frame(width: 30, height: 30)
        case .failed:
            Button(action: action) {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        default:
            Button(action: action) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textSubtle)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    let uiFont: UIFont
    let color: Color

    private let gap: CGFloat = 28
    private let pointsPerSecond: CGFloat = 24

    private var measuredTextWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: uiFont]).width)
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width

            if availableWidth <= 0 || measuredTextWidth <= availableWidth {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                    let cycleWidth = measuredTextWidth + gap
                    let cycleDuration = Double(cycleWidth / pointsPerSecond)
                    let elapsed = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)
                    let offset = CGFloat(elapsed / cycleDuration) * cycleWidth

                    HStack(spacing: gap) {
                        label
                        label
                    }
                    .frame(width: availableWidth, alignment: .leading)
                    .offset(x: -offset)
                }
                .clipped()
            }
        }
        .frame(height: uiFont.lineHeight)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct PlaylistChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.serif(17, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.accentInk : Theme.textPrimary)
                Text("\(subtitle) songs")
                    .font(Theme.mono(9, weight: .regular))
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? Theme.accentInk.opacity(0.75) : Theme.textSubtle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isSelected ? Theme.ink : Theme.surface,
                in: RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(isSelected ? .clear : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerControlButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .frame(width: size, height: size)
                .foregroundStyle(Theme.textPrimary)
                .background(Theme.surfaceRaised, in: Circle())
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Theme.ink.opacity(configuration.isPressed ? 0.84 : 1.0),
                in: RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
            .foregroundStyle(Theme.accentInk)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Theme.surfaceRaised.opacity(configuration.isPressed ? 0.7 : 1.0),
                in: RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .foregroundStyle(Theme.textPrimary)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

