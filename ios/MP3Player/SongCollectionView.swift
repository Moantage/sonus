import SwiftUI

/// A playlist or collection page: tinted header with artwork, a download toggle, a big play
/// button, and the songs.
struct SongCollectionView: View {
    let collection: SongCollection

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var shell: ShellState
    @Environment(\.dismiss) private var dismiss

    @State private var showsTitleInBar = false
    @State private var isActionsSheetPresented = false
    @State private var isAddSongsPresented = false
    @State private var isConfirmingDeletePlaylist = false
    @State private var isConfirmingRemoveDownloads = false

    private static let scrollSpace = "SongCollectionView.scroll"

    private var songs: [Song] { collection.songs(in: libraryStore) }
    private var title: String { collection.title(in: libraryStore) }
    private var context: PlayContext { .collection(collection, in: libraryStore) }
    private var playlist: Playlist? { libraryStore.playlist(with: collection.playlistID) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                actionRow
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if songs.isEmpty {
                    emptyState
                } else {
                    SongList(songs: songs, context: context)
                }
            }
            .padding(.horizontal, ScreenMetrics.pageMargin)
            .padding(.bottom, 24)
            .background(alignment: .top) { headerGlow }
        }
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(TitleScrolledPastKey.self) { isScrolledPast in
            showsTitleInBar = isScrolledPast
        }
        .background(Theme.backgroundBase)
        .navigationTitle(showsTitleInBar ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackground(Theme.backgroundElevated, visibility: showsTitleInBar ? .visible : .hidden)
        .animation(.easeOut(duration: 0.2), value: showsTitleInBar)
        .sheet(isPresented: $isActionsSheetPresented) { playlistActionsSheet }
        .sheet(isPresented: $isAddSongsPresented) {
            if let playlist { AddSongsSheet(playlistID: playlist.id) }
        }
        .confirmationDialog(
            "Delete “\(title)”?",
            isPresented: $isConfirmingDeletePlaylist,
            titleVisibility: .visible
        ) {
            Button("Delete playlist", role: .destructive) {
                if let playlist {
                    libraryStore.deletePlaylist(playlist)
                    shell.showToast("Deleted “\(playlist.name)”")
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The songs stay in your library.")
        }
        .confirmationDialog(
            "Remove downloads?",
            isPresented: $isConfirmingRemoveDownloads,
            titleVisibility: .visible
        ) {
            Button("Remove downloads", role: .destructive) { removeDownloads() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The songs stay in your library and you can download them again.")
        }
        .onChange(of: libraryStore.playlists) { playlists in
            // The playlist was deleted (here or by sync): leave its page.
            if let id = collection.playlistID, !playlists.contains(where: { $0.id == id }) {
                dismiss()
            }
        }
    }

    // MARK: Header

    private var headerGlow: some View {
        let seed = collection.playlistID ?? songs.first?.id ?? UUID()
        return LinearGradient(
            colors: [ArtworkPalette.backdrop(from: ArtworkPalette.baseColor(for: seed)), Theme.backgroundBase],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 520)
        .padding(.horizontal, -ScreenMetrics.pageMargin)
        .offset(y: -200)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            CollectionArtwork(collection: collection, songs: songs, size: ScreenMetrics.collectionArtwork)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 28, y: 16)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Text(title)
                .font(.emberHero)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)
                .background(
                    // Once the title scrolls out of view, it moves into the navigation bar.
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TitleScrolledPastKey.self,
                            value: proxy.frame(in: .named(Self.scrollSpace)).maxY < 0
                        )
                    }
                )

            Text(metadata)
                .font(.subheadline)
                .foregroundStyle(Theme.textSubtle)
        }
    }

    private var metadata: String {
        let kind = collection.playlistID == nil ? "Collection" : "Playlist"
        let count = songs.count == 1 ? "1 song" : "\(songs.count) songs"
        let total = songs.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return "\(kind) · \(count)" }
        let minutes = Int(total / 60)
        let length = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(max(minutes, 1)) min"
        return "\(kind) · \(count) · \(length)"
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 6) {
            if !songs.isEmpty {
                downloadToggle
            }

            if playlist != nil {
                Button {
                    isActionsSheetPresented = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textSubtle)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("More options for \(title)")
            }

            Spacer()

            if songs.count > 1 {
                Button {
                    shell.shufflePlay(songs, context: context, player: player)
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .symbolBounce(value: shell.shuffleRequestCount)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Shuffle \(title)")
                .padding(.trailing, 4)
            }

            if !songs.isEmpty {
                let isPlaying = shell.isPlaying(context, player: player)
                Button {
                    shell.playCollection(songs, context: context, player: player)
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .symbolReplaceTransition()
                        .frame(width: 58, height: 58)
                        .background(Theme.playGradient, in: Circle())
                        .shadow(color: Theme.accent.opacity(0.4), radius: 14, y: 5)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.9))
                .accessibilityLabel(isPlaying ? "Pause \(title)" : "Play \(title)")
            }
        }
    }

    private var downloadStatus: (allOnDevice: Bool, isDownloading: Bool) {
        let isDownloading = songs.contains { song in
            if case .downloading = downloadManager.state(for: song) { return true }
            return false
        }
        return (songs.allSatisfy(\.isDownloadedLocally), isDownloading)
    }

    private var downloadToggle: some View {
        let status = downloadStatus
        return Button {
            toggleDownloads(allOnDevice: status.allOnDevice)
        } label: {
            ZStack {
                if status.isDownloading {
                    ProgressView().tint(Theme.accent)
                } else {
                    Image(systemName: status.allOnDevice ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(status.allOnDevice ? Theme.accent : Theme.textSubtle)
                        .symbolReplaceTransition()
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(status.isDownloading)
        .haptic(.success, trigger: status.allOnDevice) { isOn in isOn }
        .accessibilityLabel("Download")
        .accessibilityValue(status.isDownloading ? "Downloading" : (status.allOnDevice ? "On this device" : "Not downloaded"))
        .accessibilityToggleTrait()
    }

    private func toggleDownloads(allOnDevice: Bool) {
        if allOnDevice {
            if songs.contains(where: LibraryActions.canRemoveDownload) {
                isConfirmingRemoveDownloads = true
            } else {
                shell.showToast("These songs are stored on this device")
            }
            return
        }
        let missing = songs.filter(\.isCloudOnly)
        for song in missing {
            LibraryActions.download(song, library: libraryStore, downloads: downloadManager)
        }
        shell.showToast(missing.count == 1 ? "Downloading 1 song" : "Downloading \(missing.count) songs")
    }

    private func removeDownloads() {
        let removable = songs.filter(LibraryActions.canRemoveDownload)
        for song in removable {
            downloadManager.removeDownload(song)
        }
        shell.showToast(removable.count == 1 ? "Removed 1 download" : "Removed \(removable.count) downloads")
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text(collection.playlistID == nil ? "Nothing here yet" : "Let's find songs for your playlist")
                .font(.system(.title3).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if playlist != nil {
                Button("Add songs") { isAddSongsPresented = true }
                    .buttonStyle(PillButtonStyle(kind: .light))
                    .frame(maxWidth: 220)
            } else {
                Text("Import music or download songs to fill this list.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSubtle)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: Playlist sheet

    private var playlistActionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CollectionArtwork(collection: collection, songs: songs, size: 48)
                Text(title)
                    .font(.system(.body).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
            }
            .padding(.bottom, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.bottom, 6)

            SheetActionRow(icon: "plus.circle", title: "Add songs") {
                isActionsSheetPresented = false
                Task {
                    try? await Task.sleep(seconds: 0.4)
                    isAddSongsPresented = true
                }
            }
            SheetActionRow(icon: "trash", title: "Delete playlist", role: .destructive) {
                isActionsSheetPresented = false
                Task {
                    try? await Task.sleep(seconds: 0.4)
                    isConfirmingDeletePlaylist = true
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .fittedSheet()
    }
}

/// Whether a collection page's title has scrolled out of view.
private struct TitleScrolledPastKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// "Add to this playlist": every song in the library with a toggle.
struct AddSongsSheet: View {
    let playlistID: Playlist.ID

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var playlist: Playlist? { libraryStore.playlist(with: playlistID) }

    var body: some View {
        CompatNavigationStack {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(LibrarySearch.rank(query, in: libraryStore.songs)) { song in
                        row(song)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Theme.backgroundElevated)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your library")
            .navigationTitle("Add to this playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .emberSheet(detents: [.large], background: Theme.backgroundElevated, cornerRadius: 20)
    }

    private func row(_ song: Song) -> some View {
        let isIn = playlist?.songIDs.contains(song.id) == true
        return Button {
            guard let playlist else { return }
            if isIn {
                libraryStore.removeSong(song, from: playlist)
            } else {
                libraryStore.addSong(song, to: playlist)
            }
        } label: {
            HStack(spacing: 12) {
                SongArtwork(id: song.id, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.emberRowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(song.displayArtist)
                        .font(.emberRowSubtitle)
                        .foregroundStyle(Theme.textSubtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: isIn ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isIn ? Theme.accent : Theme.textSubtle)
                    .symbolReplaceTransition()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .haptic(.selection, trigger: isIn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(song.title), \(song.displayArtist)")
        .accessibilityValue(isIn ? "In playlist" : "Not in playlist")
        .accessibilityHint(isIn ? "Removes it from the playlist" : "Adds it to the playlist")
        .accessibilityAddTraits(.isButton)
    }
}
