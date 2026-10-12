import SwiftUI

/// Advanced playback controls (free for everyone): pitch-preserved playback speed, 15-second
/// skips and a sleep timer.
struct AdvancedControlsSheet: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var sleepMinutes = 15
    @State private var skipCount = 0
    private let sleepPresets = [5, 15, 30, 45, 60]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    speedSection
                    skipSection
                    sleepSection
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.backgroundElevated)
            .navigationTitle("Playback controls")
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

    // MARK: - Speed

    private var speedSection: some View {
        card(title: "Playback speed", systemImage: "speedometer") {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(AudioPlayerManager.availableSpeeds, id: \.self) { speed in
                        FilterPill(title: speedLabel(speed), isSelected: abs(player.playbackSpeed - speed) < 0.001) {
                            player.setPlaybackSpeed(speed)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .sensoryFeedback(.selection, trigger: player.playbackSpeed)
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        speed == 1.0 ? "1×" : String(format: "%g×", speed)
    }

    // MARK: - Skip

    private var skipSection: some View {
        card(title: "Skip", systemImage: "goforward.15") {
            HStack(spacing: 12) {
                skipButton(icon: "gobackward.15", label: "Back 15s") { player.skipBackward(15) }
                skipButton(icon: "goforward.15", label: "Forward 15s") { player.skipForward(15) }
            }
        }
    }

    private func skipButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            skipCount += 1
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Text(label).font(.system(.caption, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96))
        .sensoryFeedback(.impact(weight: .light), trigger: skipCount)
    }

    // MARK: - Sleep timer

    private var sleepSection: some View {
        card(title: "Sleep timer", systemImage: "moon.zzz.fill") {
            if let endsAt = player.sleepTimerEndsAt {
                VStack(spacing: 12) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, endsAt.timeIntervalSince(context.date))
                        Text("Pausing in \(remaining.mmssString)")
                            .font(.system(.title3, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .monospacedDigit()
                    }
                    Button("Turn off timer") {
                        player.cancelSleepTimer()
                    }
                    .buttonStyle(PillButtonStyle(kind: .surface))
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 14) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(sleepPresets, id: \.self) { minutes in
                                FilterPill(title: "\(minutes) min", isSelected: sleepMinutes == minutes) {
                                    sleepMinutes = minutes
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    PrimaryButton(title: "Start timer") {
                        player.setSleepTimer(minutes: sleepMinutes)
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: player.sleepTimerEndsAt) { _, new in new != nil }
    }

    // MARK: - Card

    private func card(title: String, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .emberCard(cornerRadius: Theme.Radius.tile)
    }
}

#Preview {
    AdvancedControlsSheet()
        .environmentObject(AudioPlayerManager())
}
