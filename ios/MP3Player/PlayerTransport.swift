import SwiftUI

/// Now Playing's transport row: playback controls sheet, previous, play/pause, next, repeat.
struct PlayerTransport: View {
    /// Whether there's a song after this one; Next dims when there isn't.
    let hasNext: Bool
    let onShowControls: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager

    @State private var previousTapCount = 0
    @State private var nextTapCount = 0

    var body: some View {
        HStack {
            controlsButton
            Spacer()
            Button {
                previousTapCount += 1
                player.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.textPrimary)
                    .symbolEffect(.bounce.down, value: previousTapCount)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.86))
            .accessibilityLabel("Previous")
            Spacer()
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 76, height: 76)
                    .background(Theme.playGradient, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(player.isPlaying ? 0.5 : 0.25), radius: player.isPlaying ? 22 : 12, y: 6)
                    .animation(Theme.Motion.snappy, value: player.isPlaying)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.9))
            .sensoryFeedback(.impact(weight: .medium), trigger: player.isPlaying)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button {
                nextTapCount += 1
                player.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(!hasNext ? Theme.textMuted : Theme.textPrimary)
                    .symbolEffect(.bounce.down, value: nextTapCount)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.86))
            .disabled(!hasNext)
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
                    .contentTransition(.symbolEffect(.replace))
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
        Button(action: onShowControls) {
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
}

/// A peek at the next song that opens the queue.
struct UpNextBar: View {
    let upNext: Song?
    let onOpenQueue: () -> Void

    var body: some View {
        Button(action: onOpenQueue) {
            HStack(spacing: 10) {
                if let upNext {
                    SongArtwork(id: upNext.id, size: 28, cornerRadius: 5)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("UP NEXT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Theme.textSubtle)
                        Text(upNext.title)
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    .id(upNext.id)
                    .transition(.opacity)
                } else {
                    Image(systemName: "text.line.last.and.arrowtriangle.forward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSubtle)
                    Text("Last song in the queue")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textSubtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSubtle)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(height: 44)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .animation(Theme.Motion.snappy, value: upNext?.id)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .accessibilityLabel(upNext.map { "Queue. Up next: \($0.title)" } ?? "Queue")
        .accessibilityHint("Shows what plays next")
    }
}
