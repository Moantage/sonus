import SwiftUI

/// The full-screen player. It grows out of the mini-player, and dragging it down (or the
/// chevron) shrinks it back. Behind it, the artwork glows and slowly drifts while music plays.
/// Swiping the artwork sideways skips, like flicking through records.
struct NowPlayingView: View {
    let namespace: Namespace.ID

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var shell: ShellState

    @State private var dragOffset: CGFloat = 0
    @State private var showsContent = false
    @State private var sheet: PlayerSheet?
    /// Sideways travel of the artwork while it's being swiped to skip.
    @State private var artworkOffset: CGFloat = 0
    /// Which way a drag on the artwork was locked to once it started moving.
    @State private var artworkDragAxis: Axis?
    @State private var skipCount = 0

    private enum PlayerSheet: Identifiable {
        case actions(Song)
        case addToPlaylist(Song)
        case queue
        case controls

        var id: String {
            switch self {
            case .actions(let song): return "actions-\(song.id)"
            case .addToPlaylist(let song): return "add-\(song.id)"
            case .queue: return "queue"
            case .controls: return "controls"
            }
        }
    }

    private var upNext: Song? {
        guard let current = player.currentSong,
              let index = player.activeQueue.firstIndex(where: { $0.id == current.id }),
              index + 1 < player.activeQueue.count else { return nil }
        return player.activeQueue[index + 1]
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.top, 4)

                Spacer(minLength: 12)

                artwork
                    .padding(.horizontal, 4)
                    .layoutPriority(-1)

                Spacer(minLength: 24)

                titleRow
                    .padding(.bottom, 16)

                PlaybackScrubber(
                    currentTime: player.currentTime,
                    duration: player.duration,
                    onSeek: { player.seek(to: $0) }
                )
                .padding(.bottom, 8)

                PlayerTransport(hasNext: upNext != nil) { sheet = .controls }
                    .padding(.bottom, 18)

                HStack(spacing: 12) {
                    RoutePickerButton()
                        .frame(width: 44, height: 44)
                    UpNextBar(upNext: upNext) { sheet = .queue }
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .opacity(showsContent ? 1 : 0)
        }
        // Moving the frame (instead of `.offset`) keeps the shrink animation starting from where
        // the finger let go.
        .padding(.top, dragOffset)
        .padding(.bottom, -dragOffset)
        .gesture(dismissGesture)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.08)) { showsContent = true }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .actions(let song):
                SongActionsSheet(song: song, playlistID: shell.playContext.playlistID)
            case .addToPlaylist(let song):
                SongActionsSheet(song: song, startsWithPlaylistPicker: true)
            case .queue:
                QueueSheet()
            case .controls:
                AdvancedControlsSheet()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: skipCount)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { collapse() }
    }

    // MARK: Background

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: dragOffset > 0 ? 32 : 0, style: .continuous)
        return shape
            .fill(Theme.backgroundBase)
            .overlay {
                AmbientArtworkBackdrop(
                    songID: player.currentSong?.id,
                    image: player.artworkImage,
                    tint: shell.artworkTint,
                    isPlaying: player.isPlaying
                )
            }
            .clipShape(shape)
            .matchedGeometryEffect(id: PlayerGeometry.background, in: namespace)
            .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: collapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.1), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close Now Playing")

            VStack(spacing: 1) {
                Text(shell.playContext.isShuffled ? "SHUFFLING FROM" : "PLAYING FROM")
                    .font(.system(.caption2, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSubtle)
                Text(shell.playContext.name)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            Button {
                if let song = player.currentSong { sheet = .actions(song) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.1), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("More options")
        }
    }

    // MARK: Artwork

    private var artwork: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            SongArtwork(
                id: player.currentSong?.id ?? UUID(),
                image: player.artworkImage,
                size: side,
                cornerRadius: Theme.Radius.hero
            )
            .matchedGeometryEffect(id: PlayerGeometry.artwork, in: namespace)
            .shadow(color: Color(shell.artworkTint).opacity(0.45), radius: 40, y: 18)
            .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
            .scaleEffect(player.isPlaying ? 1 : 0.88)
            .animation(Theme.Motion.bounce, value: player.isPlaying)
            .offset(x: artworkOffset)
            .rotationEffect(.degrees(Double(artworkOffset / max(side, 1)) * 6))
            .opacity(1 - min(abs(artworkOffset) / max(side, 1), 1) * 0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(artworkGesture(width: side))
            .onTapGesture(count: 2) { player.togglePlayback() }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Artwork")
        .accessibilityHint("Swipe sideways to change songs, double-tap to play or pause")
        .accessibilityAction { player.togglePlayback() }
        .accessibilityAction(named: "Next track") { player.playNext() }
        .accessibilityAction(named: "Previous track") { player.playPrevious() }
    }

    /// Horizontal drags skip with a record-flick feel; vertical drags close the player, as
    /// they do everywhere else on this screen.
    private func artworkGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if artworkDragAxis == nil {
                    artworkDragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                switch artworkDragAxis {
                case .horizontal:
                    let canGo = value.translation.width < 0 ? upNext != nil : true
                    // Rubber-band when there's nowhere to go.
                    artworkOffset = canGo ? value.translation.width : value.translation.width * 0.25
                case .vertical:
                    dismissChanged(value)
                case nil:
                    break
                }
            }
            .onEnded { value in
                defer { artworkDragAxis = nil }
                guard artworkDragAxis == .horizontal else {
                    dismissEnded(value)
                    return
                }
                let travel = value.translation.width
                let projected = value.predictedEndTranslation.width
                let goesNext = (travel < -80 || projected < -240) && upNext != nil
                let goesBack = travel > 80 || projected > 240
                guard goesNext || goesBack else {
                    withAnimation(Theme.Motion.bounce) { artworkOffset = 0 }
                    return
                }
                let exit = (goesNext ? -1 : 1) * width * 1.2
                withAnimation(.easeIn(duration: 0.16)) {
                    artworkOffset = exit
                } completion: {
                    if goesNext { player.playNext() } else { player.playPrevious() }
                    skipCount += 1
                    artworkOffset = -exit * 0.6
                    withAnimation(Theme.Motion.glide) { artworkOffset = 0 }
                }
            }
    }

    // MARK: Title

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentSong?.title ?? "")
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(player.currentSong?.displayArtist ?? "")
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Theme.textSubtle)
                    .lineLimit(1)
            }
            .id(player.currentSong?.id)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8)),
                removal: .opacity
            ))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button {
                if let song = player.currentSong { sheet = .addToPlaylist(song) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Add to playlist")
        }
        .animation(Theme.Motion.snappy, value: player.currentSong?.id)
    }

    // MARK: Dismiss

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged(dismissChanged)
            .onEnded(dismissEnded)
    }

    private func dismissChanged(_ value: DragGesture.Value) {
        guard value.translation.height > 0,
              value.translation.height > abs(value.translation.width) else { return }
        dragOffset = value.translation.height
    }

    private func dismissEnded(_ value: DragGesture.Value) {
        let shouldClose = value.translation.height > 140 || value.predictedEndTranslation.height > 420
        if shouldClose, dragOffset > 0 {
            collapse()
        } else {
            withAnimation(Theme.Motion.snappy) { dragOffset = 0 }
        }
    }

    private func collapse() {
        withAnimation(Theme.Motion.glide) {
            shell.isPlayerExpanded = false
            dragOffset = 0
        }
    }
}
