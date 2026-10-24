import SwiftUI

/// Your Library: collections and playlists, filterable with pills. "+" creates a playlist or
/// imports music.
struct LibraryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case playlists = "Playlists"
        case songs = "Songs"
        case downloaded = "Downloaded"

        var id: Self { self }
    }

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var shell: ShellState

    @State private var filter: Filter?
    @State private var isAddSheetPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TabHeader(title: "Your Library") {
                    HeaderIconButton(systemImage: "plus", label: "Create playlist or import music") {
                        isAddSheetPresented = true
                    }
                }

                filterBar

                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.backgroundBase)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAddSheetPresented) {
            AddToLibrarySheet()
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    // MARK: Filters

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if filter != nil {
                    Button {
                        withAnimation(.snappy) { filter = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(Theme.surfaceRaised, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Clear filter")
                }

                ForEach(Filter.allCases) { option in
                    if filter == nil || filter == option {
                        FilterPill(title: option.rawValue, isSelected: filter == option) {
                            withAnimation(.snappy) { filter = filter == option ? nil : option }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch filter {
        case nil:
            if libraryStore.songs.isEmpty && libraryStore.playlists.isEmpty {
                EmptyLibraryCard()
            } else {
                VStack(spacing: 4) {
                    LibraryItemRow(collection: .allSongs, isPinned: true)
                    if !libraryStore.songs.isEmpty {
                        LibraryItemRow(collection: .recentlyAdded)
                    }
                    if libraryStore.songs.contains(where: \.isDownloadedLocally),
                       libraryStore.songs.contains(where: { $0.remoteURL != nil }) {
                        LibraryItemRow(collection: .downloaded)
                    }
                    playlistRows
                    // Always end on a way forward, so the page is never a dead end.
                    createPlaylistRow
                }
            }
        case .playlists:
            VStack(spacing: 4) {
                playlistRows
                createPlaylistRow
            }
        case .songs:
            if libraryStore.songs.isEmpty {
                EmptyLibraryCard()
            } else {
                SongList(songs: libraryStore.songs, context: .library)
            }
        case .downloaded:
            let downloaded = SongCollection.downloaded.songs(in: libraryStore)
            if downloaded.isEmpty {
                EmptyStateText(
                    title: "Nothing downloaded yet",
                    message: "Songs you download from your servers appear here and play without a connection."
                )
            } else {
                SongList(songs: downloaded, context: .collection(.downloaded, in: libraryStore))
            }
        }
    }

    private var playlistRows: some View {
        ForEach(libraryStore.playlists) { playlist in
            LibraryItemRow(collection: .playlist(playlist.id))
        }
    }

    private var createPlaylistRow: some View {
        Button {
            shell.startCreatingPlaylist()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 64, height: 64)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous)
                            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Create playlist")
                        .font(.emberRowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Group songs for a mood, a trip, a workout")
                        .font(.emberRowSubtitle)
                        .foregroundStyle(Theme.textSubtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }
}

/// A collection or playlist in Your Library and search results. Opens its page.
struct LibraryItemRow: View {
    let collection: SongCollection
    var isPinned = false

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var shell: ShellState

    var body: some View {
        let songs = collection.songs(in: libraryStore)
        let isPlaying = shell.isPlaying(.collection(collection, in: libraryStore), player: player)
        Button {
            shell.push(.collection(collection))
        } label: {
            HStack(spacing: 12) {
                CollectionArtwork(collection: collection, songs: songs, size: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.title(in: libraryStore))
                        .font(.emberRowTitle)
                        .foregroundStyle(isPlaying ? Theme.accent : Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.accent)
                                .rotationEffect(.degrees(45))
                        }
                        Text(subtitle(count: songs.count))
                            .font(.emberRowSubtitle)
                            .foregroundStyle(Theme.textSubtle)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isPlaying {
                    EqualizerBars(isAnimating: true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.title(in: libraryStore)), \(subtitle(count: songs.count))")
        .accessibilityValue(isPlaying ? "Playing" : "")
        .accessibilityHint("Opens the list")
        .accessibilityAddTraits(.isButton)
    }

    private func subtitle(count: Int) -> String {
        let songs = count == 1 ? "1 song" : "\(count) songs"
        switch collection {
        case .playlist: return "Playlist · \(songs)"
        default: return "Collection · \(songs)"
        }
    }
}

/// Centered title + message for empty lists.
struct EmptyStateText: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSubtle)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 12)
    }
}

/// The "+" sheet in Your Library.
private struct AddToLibrarySheet: View {
    @EnvironmentObject private var shell: ShellState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            option(
                icon: "music.note.list",
                title: "Playlist",
                message: "Build a playlist from your songs"
            ) {
                shell.startCreatingPlaylist()
            }
            option(
                icon: "square.and.arrow.down",
                title: "Import from Files",
                message: "Add audio files from your iPhone, iCloud Drive or a connected server"
            ) {
                shell.isImporterPresented = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .fittedSheet()
    }

    private func option(icon: String, title: String, message: String, action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            Task {
                // Let the sheet finish dismissing before the next screen appears.
                try? await Task.sleep(for: .milliseconds(400))
                action()
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 52, height: 52)
                    .background(Theme.surfaceRaised, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }
}
