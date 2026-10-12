import AVKit
import SwiftUI

// MARK: - Scrubber

/// A thin progress line with a knob. Drag or tap to seek; VoiceOver adjusts in 10s steps.
struct PlaybackScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragProgress: Double?

    private var progress: Double {
        if let dragProgress { return dragProgress }
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let isDragging = dragProgress != nil
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.24))
                        .frame(height: isDragging ? 6 : 4)
                    Capsule()
                        .fill(Theme.textPrimary)
                        .frame(width: max(width * progress, 4), height: isDragging ? 6 : 4)
                    Circle()
                        .fill(Theme.textPrimary)
                        .frame(width: isDragging ? 16 : 12, height: isDragging ? 16 : 12)
                        .offset(x: width * progress - (isDragging ? 8 : 6))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            withAnimation(.easeOut(duration: 0.1)) {
                                dragProgress = min(max(value.location.x / max(width, 1), 0), 1)
                            }
                        }
                        .onEnded { _ in
                            if let dragProgress { onSeek(dragProgress * duration) }
                            withAnimation(.easeOut(duration: 0.15)) { dragProgress = nil }
                        }
                )
            }
            .frame(height: 24)

            HStack {
                Text((progress * duration).mmssString)
                Spacer()
                Text("-" + max(duration - progress * duration, 0).mmssString)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.textSubtle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Track position")
        .accessibilityValue("\(currentTime.mmssString) of \(duration.mmssString)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(currentTime + 10)
            case .decrement: onSeek(currentTime - 10)
            @unknown default: break
            }
        }
    }
}

// MARK: - AirPlay

/// The system AirPlay / Bluetooth route picker.
struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(Theme.textSubtle)
        view.activeTintColor = UIColor(Theme.accent)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Queue

/// Read-only view of what's playing and what's next. Tapping a song jumps to it.
struct QueueSheet: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var shell: ShellState
    @Environment(\.dismiss) private var dismiss

    private var currentIndex: Int? {
        guard let current = player.currentSong else { return nil }
        return player.activeQueue.firstIndex { $0.id == current.id }
    }

    private var upNext: [Song] {
        guard let currentIndex else { return [] }
        return Array(player.activeQueue.dropFirst(currentIndex + 1))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let current = player.currentSong {
                        Text("Now playing")
                            .font(.emberSection)
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        row(current)
                    }

                    Text("Next from: \(shell.playContext.name)")
                        .font(.emberSection)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 16)
                        .accessibilityAddTraits(.isHeader)

                    if upNext.isEmpty {
                        Text("Nothing else in the queue. Playback stops after this song.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSubtle)
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(upNext) { song in row(song) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Theme.backgroundElevated)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.backgroundElevated)
        .presentationCornerRadius(20)
    }

    private func row(_ song: Song) -> some View {
        let isCurrent = player.currentSong?.id == song.id
        return Button {
            if !isCurrent { player.play(song: song, in: player.activeQueue) }
        } label: {
            HStack(spacing: 12) {
                SongArtwork(id: song.id, image: isCurrent ? player.artworkImage : nil, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if isCurrent { EqualizerBars(isAnimating: player.isPlaying) }
                        Text(song.title)
                            .font(.emberRowTitle)
                            .foregroundStyle(isCurrent ? Theme.accent : Theme.textPrimary)
                            .lineLimit(1)
                    }
                    Text(song.displayArtist)
                        .font(.emberRowSubtitle)
                        .foregroundStyle(Theme.textSubtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(song.title), \(song.displayArtist)")
        .accessibilityValue(isCurrent ? "Now playing" : "")
        .accessibilityHint(isCurrent ? "" : "Plays this song")
    }
}
