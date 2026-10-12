import SwiftUI

// MARK: - Song row

/// One song: artwork, title and artist, plus a "⋯" button. The playing song shows its title
/// in amber with animated equaliser bars.
struct SongRow: View {
    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool
    var artwork: UIImage?
    var downloadState: DownloadManager.State = .downloaded
    let onTap: () -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    SongArtwork(id: song.id, image: isCurrent ? artwork : nil, size: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if isCurrent {
                                EqualizerBars(isAnimating: isPlaying)
                            }
                            Text(song.title)
                                .font(.emberRowTitle)
                                .foregroundStyle(isCurrent ? Theme.accent : Theme.textPrimary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 5) {
                            downloadBadge
                            Text(song.displayArtist)
                                .font(.emberRowSubtitle)
                                .foregroundStyle(Theme.textSubtle)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(song.title), \(song.displayArtist)")
            .accessibilityValue(isCurrent ? (isPlaying ? "Now playing" : "Paused") : "")
            .accessibilityHint("Plays the song")
            .accessibilityAddTraits(.isButton)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSubtle)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("More options for \(song.title)")
        }
    }

    /// Only songs that also live on a server get a download indicator; Files imports are
    /// always on the device.
    @ViewBuilder
    private var downloadBadge: some View {
        if song.remoteURL != nil || song.remoteStoragePath != nil {
            switch downloadState {
            case .downloading:
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.accent)
                    .accessibilityLabel("Downloading")
            case .downloaded:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Downloaded")
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.error)
                    .accessibilityLabel("Download failed")
            case .notDownloaded:
                EmptyView()
            }
        }
    }
}

// MARK: - Song list

/// A list of song rows that plays in place on tap and owns the "⋯" sheet.
struct SongList: View {
    let songs: [Song]
    let context: PlayContext
    /// The full queue to play from. Defaults to `songs`; search results pass their own list.
    var queue: [Song]?

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var shell: ShellState
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var actionSong: Song?

    var body: some View {
        LazyVStack(spacing: 2) {
            ForEach(songs) { song in
                SongRow(
                    song: song,
                    isCurrent: player.currentSong?.id == song.id,
                    isPlaying: player.isPlaying,
                    artwork: player.artworkImage,
                    downloadState: downloadManager.state(for: song),
                    onTap: { shell.play(song, in: queue ?? songs, context: context, player: player) },
                    onMore: { actionSong = song }
                )
            }
        }
        .sheet(item: $actionSong) { song in
            SongActionsSheet(song: song, playlistID: context.playlistID)
        }
    }
}

// MARK: - Song actions sheet

/// The "⋯" bottom sheet: add to playlist, remove from this playlist, download, delete.
struct SongActionsSheet: View {
    let song: Song
    /// The playlist the sheet was opened from, if any.
    var playlistID: Playlist.ID?

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var shell: ShellState
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var isPickingPlaylist: Bool
    @State private var isConfirmingDelete = false

    /// - Parameter startsWithPlaylistPicker: opens straight on "Add to playlist".
    init(song: Song, playlistID: Playlist.ID? = nil, startsWithPlaylistPicker: Bool = false) {
        self.song = song
        self.playlistID = playlistID
        _isPickingPlaylist = State(initialValue: startsWithPlaylistPicker)
    }

    private var playlist: Playlist? { libraryStore.playlist(with: playlistID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.bottom, 6)

            if isPickingPlaylist {
                playlistPicker
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                actions
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .fittedSheet()
        .confirmationDialog(
            "Delete “\(song.title)” from your library?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                libraryStore.deleteSong(song)
                shell.showToast("Deleted from your library")
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The song and its file are removed from this device.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SongArtwork(
                id: song.id,
                image: player.currentSong?.id == song.id ? player.artworkImage : nil,
                size: 48
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(song.displayArtist)
                    .font(.emberRowSubtitle)
                    .foregroundStyle(Theme.textSubtle)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            SheetActionRow(icon: "plus.circle", title: "Add to playlist") {
                withAnimation(.snappy) { isPickingPlaylist = true }
            }

            if let playlist {
                SheetActionRow(icon: "minus.circle", title: "Remove from this playlist") {
                    libraryStore.removeSong(song, from: playlist)
                    shell.showToast("Removed from \(playlist.name)")
                    dismiss()
                }
            }

            downloadAction

            SheetActionRow(icon: "trash", title: "Delete from library", role: .destructive) {
                isConfirmingDelete = true
            }
        }
    }

    @ViewBuilder
    private var downloadAction: some View {
        switch downloadManager.state(for: song) {
        case .downloading:
            SheetActionRow(icon: "arrow.down.circle", title: "Downloading…", isEnabled: false) { }
        case .downloaded where LibraryActions.canRemoveDownload(song):
            SheetActionRow(icon: "arrow.down.circle.fill", title: "Remove download", tint: Theme.accent) {
                downloadManager.removeDownload(song)
                shell.showToast("Download removed")
                dismiss()
            }
        case .notDownloaded, .failed:
            if song.isCloudOnly {
                SheetActionRow(icon: "arrow.down.circle", title: "Download") {
                    LibraryActions.download(song, library: libraryStore, downloads: downloadManager)
                    shell.showToast("Downloading “\(song.title)”")
                    dismiss()
                }
            }
        default:
            EmptyView()
        }
    }

    private var playlistPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { isPickingPlaylist = false }
            } label: {
                Label("Add to playlist", systemImage: "chevron.left")
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Back")

            SheetActionRow(icon: "plus", title: "New playlist", tint: Theme.accent) {
                dismiss()
                Task {
                    // Let the sheet finish dismissing before the full-screen flow appears.
                    try? await Task.sleep(for: .milliseconds(400))
                    shell.startCreatingPlaylist(adding: song)
                }
            }

            ForEach(libraryStore.playlists) { playlist in
                let isIn = playlist.songIDs.contains(song.id)
                SheetActionRow(
                    icon: isIn ? "checkmark.circle.fill" : "circle",
                    title: playlist.name,
                    tint: isIn ? Theme.accent : Theme.textSubtle
                ) {
                    if isIn {
                        libraryStore.removeSong(song, from: playlist)
                        shell.showToast("Removed from \(playlist.name)")
                    } else {
                        libraryStore.addSong(song, to: playlist)
                        shell.showToast("Added to \(playlist.name)")
                    }
                    dismiss()
                }
                .accessibilityValue(isIn ? "Added" : "")
            }
        }
    }
}

/// A full-width row in a bottom sheet: icon + label.
struct SheetActionRow: View {
    let icon: String
    let title: String
    var role: ButtonRole?
    var tint: Color = Theme.textSubtle
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(role == .destructive ? Theme.error : tint)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .foregroundStyle(role == .destructive ? Theme.error : Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Fitted bottom sheet

/// Presents content as a dark bottom sheet sized to fit it, scrolling only when it doesn't.
private struct FittedSheetModifier: ViewModifier {
    @State private var contentHeight: CGFloat = 300

    func body(content: Content) -> some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.backgroundElevated)
        .presentationCornerRadius(20)
    }
}

extension View {
    func fittedSheet() -> some View {
        modifier(FittedSheetModifier())
    }
}
