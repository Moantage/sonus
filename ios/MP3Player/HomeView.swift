import SwiftUI

/// Home: a greeting, a hero card to jump straight into music (resume or shuffle everything),
/// shortcuts to your collections, recently added songs and your playlists. Everything comes
/// from the local library.
struct HomeView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var shell: ShellState

    private var recentSongs: [Song] { SongCollection.recentlyAdded.songs(in: libraryStore) }

    private var jumpBackSong: Song? {
        if let current = player.currentSong { return current }
        guard let lastID = player.lastPlayedSongID else { return nil }
        return libraryStore.songs.first { $0.id == lastID }
    }

    /// The song the hero card features: what's playing, what played last, or the newest song.
    private var heroSong: Song? { jumpBackSong ?? recentSongs.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    TabHeader(title: greeting)
                    if !libraryStore.songs.isEmpty {
                        Text(librarySummary)
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.textSubtle)
                            .padding(.leading, 46)
                    }
                }

                if libraryStore.songs.isEmpty {
                    EmptyLibraryCard()
                    if !libraryStore.playlists.isEmpty { playlistsSection }
                } else {
                    if let heroSong { HomeHeroCard(song: heroSong, isFresh: jumpBackSong == nil) }
                    shortcuts
                    recentlyAddedSection
                    playlistsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) { ambientGlow }
        .background(Theme.backgroundBase)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The top of Home takes on the colour of the featured song.
    private var ambientGlow: some View {
        let tint: UIColor = {
            guard let heroSong else { return UIColor(Theme.accent) }
            if heroSong.id == player.currentSong?.id { return shell.artworkTint }
            return ArtworkPalette.baseColor(for: heroSong.id)
        }()
        return LinearGradient(
            colors: [ArtworkPalette.backdrop(from: tint, brightness: 0.3...0.42).opacity(0.75), Theme.backgroundBase.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 460)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: tint)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// "12 songs · 48 min · 2 playlists"
    private var librarySummary: String {
        let songs = libraryStore.songs
        var parts = [songs.count == 1 ? "1 song" : "\(songs.count) songs"]
        let minutes = Int(songs.reduce(0) { $0 + $1.duration } / 60)
        if minutes > 0 {
            parts.append(minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min")
        }
        let playlists = libraryStore.playlists.count
        if playlists > 0 { parts.append(playlists == 1 ? "1 playlist" : "\(playlists) playlists") }
        return parts.joined(separator: " · ")
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        let collections: [SongCollection] = [.allSongs, .recentlyAdded]
            + libraryStore.playlists.prefix(4).map { .playlist($0.id) }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(collections, id: \.self) { collection in
                ShortcutTile(collection: collection)
            }
        }
    }

    // MARK: Recently added

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recently added", actionTitle: "Show all") {
                shell.push(.collection(.recentlyAdded))
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(recentSongs.prefix(12)) { song in
                        SongCard(song: song) {
                            shell.play(
                                song,
                                in: recentSongs,
                                context: .collection(.recentlyAdded, in: libraryStore),
                                player: player
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
        }
    }

    // MARK: Playlists

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your playlists", actionTitle: libraryStore.playlists.isEmpty ? nil : "Show all") {
                shell.selectedTab = .library
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(libraryStore.playlists) { playlist in
                        PlaylistCard(playlist: playlist)
                    }
                    NewPlaylistCard()
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
        }
    }
}

// MARK: - Cards

/// Compact two-column shortcut: artwork on the left, name on the right.
private struct ShortcutTile: View {
    let collection: SongCollection

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var shell: ShellState

    var body: some View {
        let context = PlayContext.collection(collection, in: libraryStore)
        let isPlaying = shell.isPlaying(context, player: player)
        Button {
            shell.push(.collection(collection))
        } label: {
            HStack(spacing: 10) {
                CollectionArtwork(collection: collection, songs: collection.songs(in: libraryStore), size: 56)
                Text(collection.title(in: libraryStore))
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(isPlaying ? Theme.accent : Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isPlaying {
                    EqualizerBars(isAnimating: true)
                        .padding(.trailing, 10)
                }
            }
            .frame(minHeight: 56)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous)
                    .strokeBorder(isPlaying ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .accessibilityLabel(collection.title(in: libraryStore))
        .accessibilityValue(isPlaying ? "Playing" : "")
    }
}

/// A song in a horizontal carousel. Tapping plays it in place.
private struct SongCard: View {
    let song: Song
    let action: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        let isCurrent = player.currentSong?.id == song.id
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                SongArtwork(id: song.id, image: isCurrent ? player.artworkImage : nil, size: 150, cornerRadius: Theme.Radius.artwork)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                    .overlay(alignment: .bottomTrailing) {
                        if isCurrent {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.accentInk)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 34, height: 34)
                                .background(Theme.accent, in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                                .padding(8)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(Theme.Motion.snappy, value: isCurrent)
                HStack(spacing: 5) {
                    if isCurrent { EqualizerBars(isAnimating: player.isPlaying, height: 10) }
                    Text(song.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(isCurrent ? Theme.accent : Theme.textPrimary)
                        .lineLimit(1)
                }
                Text(song.displayArtist)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSubtle)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(song.title), \(song.displayArtist)")
        .accessibilityValue(isCurrent ? (player.isPlaying ? "Now playing" : "Paused") : "")
        .accessibilityHint("Plays the song")
        .accessibilityAddTraits(.isButton)
    }
}

/// A playlist in a horizontal carousel. Tapping opens its page.
private struct PlaylistCard: View {
    let playlist: Playlist

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var shell: ShellState

    var body: some View {
        let collection = SongCollection.playlist(playlist.id)
        Button {
            shell.push(.collection(collection))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CollectionArtwork(collection: collection, songs: collection.songs(in: libraryStore), size: 150)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                Text(playlist.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(playlist.songIDs.count == 1 ? "1 song" : "\(playlist.songIDs.count) songs")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSubtle)
            }
            .frame(width: 150, alignment: .leading)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the playlist")
    }
}

private struct NewPlaylistCard: View {
    @EnvironmentObject private var shell: ShellState

    var body: some View {
        Button {
            shell.startCreatingPlaylist()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.textSubtle)
                    .frame(width: 150, height: 150)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous)
                            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                Text("New playlist")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 150, alignment: .leading)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("New playlist")
    }
}

/// The first thing on Home: the song to jump back into, set on its own blurred artwork, with
/// one button to resume and one to shuffle the whole library. Two taps from launch to music.
private struct HomeHeroCard: View {
    let song: Song
    /// Nothing has been played yet: the card features the newest song instead.
    let isFresh: Bool

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var shell: ShellState

    private var isCurrent: Bool { player.currentSong?.id == song.id }
    private var image: UIImage? { isCurrent ? player.artworkImage : nil }

    private var eyebrow: String {
        if isCurrent { return player.isPlaying ? "Now playing" : "Paused" }
        return isFresh ? "Start listening" : "Jump back in"
    }

    private var primaryTitle: String {
        if isCurrent { return player.isPlaying ? "Pause" : "Resume" }
        return "Play"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 16) {
                Button(action: openOrPlay) {
                    SongArtwork(id: song.id, image: image, size: 116, cornerRadius: 12)
                        .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
                        .scaleEffect(isCurrent && !player.isPlaying ? 0.94 : 1)
                        .animation(Theme.Motion.bounce, value: player.isPlaying)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.95))
                .accessibilityLabel(isCurrent ? "Open Now Playing" : "Play \(song.title)")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isCurrent { EqualizerBars(isAnimating: player.isPlaying, height: 10) }
                        Text(eyebrow.uppercased())
                            .font(.system(.caption2, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.accentLight)
                            .contentTransition(.opacity)
                    }
                    Text(song.title)
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(song.displayArtist)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.textSubtle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 10) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.emberButton)
                        .foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.playGradient, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96))

                Button {
                    shell.shufflePlay(libraryStore.songs, context: .library, player: player)
                } label: {
                    Label("Shuffle all", systemImage: "shuffle")
                        .symbolEffect(.bounce, value: shell.shuffleRequestCount)
                        .font(.emberButton)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96))
                .accessibilityHint("Plays your whole library in a random order")
            }
        }
        .padding(16)
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .animation(Theme.Motion.snappy, value: isCurrent)
        .animation(Theme.Motion.snappy, value: player.isPlaying)
    }

    /// The song's own artwork, blurred into a coloured light behind the card.
    private var backdrop: some View {
        ZStack {
            Theme.backgroundElevated
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    GenerativeCover(id: song.id)
                }
            }
            .scaleEffect(1.6)
            .blur(radius: 40)
            .saturation(1.2)
            .opacity(0.85)
            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .id(song.id)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.6), value: song.id)
    }

    private func primaryAction() {
        if isCurrent {
            player.togglePlayback()
        } else {
            shell.play(song, in: libraryStore.songs, context: .library, player: player)
        }
    }

    private func openOrPlay() {
        if isCurrent {
            withAnimation(Theme.Motion.glide) { shell.isPlayerExpanded = true }
        } else {
            primaryAction()
        }
    }
}

/// Shown when nothing has been imported yet.
struct EmptyLibraryCard: View {
    @EnvironmentObject private var shell: ShellState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WaveformMark(size: 44)
            Text("Your library is empty")
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Import songs from the Files app, including shared folders on your NAS that you've connected there.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSubtle)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                shell.isImporterPresented = true
            } label: {
                Label("Import music", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.accent.opacity(0.16), Theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        )
    }
}
