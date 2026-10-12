import SwiftUI

/// Home: a greeting, shortcuts to your collections, the song to jump back into, recently added
/// songs and your playlists. Everything comes from the local library.
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TabHeader(title: greeting)

                if libraryStore.songs.isEmpty {
                    EmptyLibraryCard()
                    if !libraryStore.playlists.isEmpty { playlistsSection }
                } else {
                    shortcuts
                    if let jumpBackSong { jumpBackIn(jumpBackSong) }
                    recentlyAddedSection
                    playlistsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            LinearGradient(colors: [Theme.accent.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
                .ignoresSafeArea()
        }
        .background(Theme.backgroundBase)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        let collections: [SongCollection] = [.allSongs, .recentlyAdded]
            + libraryStore.playlists.prefix(4).map { .playlist($0.id) }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(collections, id: \.self) { collection in
                ShortcutTile(collection: collection)
            }
        }
    }

    // MARK: Jump back in

    private func jumpBackIn(_ song: Song) -> some View {
        let isCurrent = player.currentSong?.id == song.id
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Jump back in")

            Button {
                shell.play(song, in: libraryStore.songs, context: .library, player: player)
            } label: {
                HStack(spacing: 14) {
                    SongArtwork(id: song.id, image: isCurrent ? player.artworkImage : nil, size: 88, cornerRadius: Theme.Radius.artwork)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isCurrent ? (player.isPlaying ? "Now playing" : "Paused") : "Last played")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(song.title)
                            .font(.system(.headline, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Text(song.displayArtist)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSubtle)
                            .lineLimit(1)
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    Image(systemName: isCurrent && player.isPlaying ? "waveform" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .symbolEffect(.variableColor.iterative, isActive: isCurrent && player.isPlaying)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: Circle())
                }
                .padding(12)
                .emberCard(cornerRadius: Theme.Radius.tile, fill: Theme.surface)
            }
            .buttonStyle(.pressable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(isCurrent ? "Now playing" : "Last played"): \(song.title), \(song.displayArtist)")
            .accessibilityHint("Plays the song")
            .accessibilityAddTraits(.isButton)
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
                SongArtwork(id: song.id, image: isCurrent ? player.artworkImage : nil, size: 140, cornerRadius: Theme.Radius.artwork)
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
            .frame(width: 140, alignment: .leading)
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
                CollectionArtwork(collection: collection, songs: collection.songs(in: libraryStore), size: 140)
                Text(playlist.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(playlist.songIDs.count == 1 ? "1 song" : "\(playlist.songIDs.count) songs")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSubtle)
            }
            .frame(width: 140, alignment: .leading)
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
                    .frame(width: 140, height: 140)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous))
                Text("New playlist")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 140, alignment: .leading)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("New playlist")
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
