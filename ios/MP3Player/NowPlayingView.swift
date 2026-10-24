import SwiftUI

/// The full-screen player. It grows out of the mini-player, and dragging it down (or the
/// chevron) shrinks it back. The background is tinted from the artwork.
struct NowPlayingView: View {
    let namespace: Namespace.ID

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var shell: ShellState

    @State private var dragOffset: CGFloat = 0
    @State private var showsContent = false
    @State private var sheet: PlayerSheet?

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

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.top, 4)

                Spacer(minLength: 12)

                artwork
                    .padding(.horizontal, 8)
                    .layoutPriority(-1)

                Spacer(minLength: 20)

                titleRow
                    .padding(.bottom, 14)

                PlaybackScrubber(
                    currentTime: player.currentTime,
                    duration: player.duration,
                    onSeek: { player.seek(to: $0) }
                )
                .padding(.bottom, 10)

                transport
                    .padding(.bottom, 14)

                bottomRow
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
            withAnimation(.easeOut(duration: 0.25).delay(0.08)) { showsContent = true }
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
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { collapse() }
    }

    // MARK: Background

    private var background: some View {
        let tint = ArtworkPalette.backdrop(from: shell.artworkTint, brightness: 0.30...0.46)
        return RoundedRectangle(cornerRadius: dragOffset > 0 ? 24 : 0, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: tint, location: 0),
                        .init(color: tint.opacity(0.55), location: 0.45),
                        .init(color: Theme.backgroundBase, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .background(Theme.backgroundBase, in: RoundedRectangle(cornerRadius: dragOffset > 0 ? 24 : 0, style: .continuous))
            .matchedGeometryEffect(id: PlayerGeometry.background, in: namespace)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: shell.artworkTint)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: collapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close Now Playing")

            VStack(spacing: 1) {
                Text("Playing from")
                    .font(.system(.caption2, weight: .semibold))
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
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
                cornerRadius: Theme.Radius.card
            )
            .matchedGeometryEffect(id: PlayerGeometry.artwork, in: namespace)
            .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
            .scaleEffect(player.isPlaying ? 1 : 0.9)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
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
                    .font(.body)
                    .foregroundStyle(Theme.textSubtle)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button {
                if let song = player.currentSong { sheet = .addToPlaylist(song) }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Add to playlist")
        }
    }

    // MARK: Transport

    private var transport: some View {
        HStack {
            controlsButton
            Spacer()
            Button {
                player.playPrevious()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Previous")
            Spacer()
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 72, height: 72)
                    .background(Theme.playGradient, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 6)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.92))
            .sensoryFeedback(.impact(weight: .medium), trigger: player.isPlaying)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button {
                player.playNext()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Next")
            Spacer()
            repeatButton
        }
        .sensoryFeedback(.selection, trigger: player.currentSong?.id)
    }

    private var repeatButton: some View {
        let isOn = player.repeatMode == .one
        return Button {
            player.cycleRepeatMode()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: player.repeatMode.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.accent : Theme.textSubtle)
                Circle()
                    .fill(isOn ? Theme.accent : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: player.repeatMode)
        .accessibilityLabel("Repeat")
        .accessibilityValue(isOn ? "Repeat this song" : "Off")
    }

    /// Playback speed, 15-second skips and the sleep timer.
    private var controlsButton: some View {
        Button {
            sheet = .controls
        } label: {
            ZStack {
                if player.playbackSpeed != 1 {
                    Text(String(format: "%g×", player.playbackSpeed))
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: player.sleepTimerEndsAt == nil ? "slider.horizontal.3" : "moon.zzz.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(player.sleepTimerEndsAt == nil ? Theme.textSubtle : Theme.accent)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Playback controls")
        .accessibilityHint("Speed, skip and sleep timer")
    }

    // MARK: Bottom row

    private var bottomRow: some View {
        HStack {
            RoutePickerButton()
                .frame(width: 44, height: 44)
            Spacer()
            Button {
                sheet = .queue
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textSubtle)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Queue")
        }
    }

    // MARK: Dismiss

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.translation.height > 0,
                      value.translation.height > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let shouldClose = value.translation.height > 140 || value.predictedEndTranslation.height > 420
                if shouldClose, dragOffset > 0 {
                    collapse()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragOffset = 0 }
                }
            }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            shell.isPlayerExpanded = false
        }
    }
}
