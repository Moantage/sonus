import SwiftUI

/// IDs shared by the mini-player and Now Playing for the expand animation.
enum PlayerGeometry {
    static let background = "player.background"
    static let artwork = "player.artwork"
}

/// The persistent bar above the tab bar: artwork, title/artist, play/pause and a thin progress
/// line. Tap to expand into Now Playing; swipe left or right to skip; swipe up to expand.
struct MiniPlayerView: View {
    let namespace: Namespace.ID

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var shell: ShellState

    @State private var dragOffset: CGFloat = 0
    @State private var skipCount = 0

    static let height: CGFloat = 64

    var body: some View {
        ZStack {
            if !shell.isPlayerExpanded, let song = player.currentSong {
                content(for: song)
            }
        }
        .frame(height: Self.height)
        // A compact bar like the tab bar: text stops growing at xLarge so it always fits; VoiceOver
        // still reads the full title and artist.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func content(for song: Song) -> some View {
        HStack(spacing: 10) {
            SongArtwork(id: song.id, image: player.artworkImage, size: 46, cornerRadius: 8)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .matchedGeometryEffect(id: PlayerGeometry.artwork, in: namespace)

            titles(for: song)

            playPauseButton
            nextButton
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(ArtworkPalette.backdrop(from: shell.artworkTint, brightness: 0.24...0.36))
                .overlay {
                    // Top light, so the bar reads as a lit pane floating over the content.
                    LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center)
                }
                .matchedGeometryEffect(id: PlayerGeometry.background, in: namespace)
        }
        .overlay(alignment: .bottom) {
            progressLine
                .padding(.horizontal, 12)
                .padding(.bottom, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .animation(.easeInOut(duration: 0.5), value: shell.artworkTint)
        .contentShape(Rectangle())
        .onTapGesture { expand() }
        .gesture(swipeGesture)
        .sensoryFeedback(.impact(weight: .medium), trigger: skipCount)
        .accessibilityElement(children: .contain)
    }

    /// Title and artist. Follows the finger while swiping to skip.
    private func titles(for song: Song) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(song.title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(song.displayArtist)
                .font(.footnote)
                .foregroundStyle(Theme.textSubtle)
                .lineLimit(1)
        }
        .offset(x: dragOffset)
        .opacity(1 - min(abs(dragOffset) / 160, 0.6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now playing: \(song.title), \(song.displayArtist)")
        .accessibilityHint("Opens Now Playing")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { expand() }
        .accessibilityAction(named: "Next track") { player.playNext() }
        .accessibilityAction(named: "Previous track") { player.playPrevious() }
    }

    private var playPauseButton: some View {
        Button {
            player.togglePlayback()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.impact(weight: .light), trigger: player.isPlaying)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }

    private var nextButton: some View {
        Button {
            skipCount += 1
            player.playNext()
        } label: {
            Image(systemName: "forward.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .symbolEffect(.bounce.down, value: skipCount)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Next track")
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textPrimary.opacity(0.18))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: proxy.size.width * min(max(player.progress, 0), 1))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = value.translation.width * 0.6
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if abs(horizontal) > abs(vertical), abs(horizontal) > 60 {
                    if horizontal < 0 {
                        player.playNext()
                    } else {
                        player.playPrevious()
                    }
                    skipCount += 1
                } else if vertical < -30, abs(vertical) > abs(horizontal) {
                    expand()
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
            }
    }

    private func expand() {
        withAnimation(Theme.Motion.glide) {
            shell.isPlayerExpanded = true
        }
    }
}
