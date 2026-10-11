import SwiftUI

/// Premium "advanced audio controls": pitch-preserved playback speed,
/// precise 15-second skip, and a sleep timer.
struct AdvancedControlsSheet: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var sleepMinutes: Double = 15
    private let sleepPresets = [5, 15, 30, 45, 60]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        speedSection
                        skipSection
                        sleepSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Advanced Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Speed

    private var speedSection: some View {
        card(title: "Playback Speed", systemImage: "speedometer") {
            HStack(spacing: 8) {
                ForEach(AudioPlayerManager.availableSpeeds, id: \.self) { speed in
                    let selected = abs(player.playbackSpeed - speed) < 0.001
                    Button {
                        player.setPlaybackSpeed(speed)
                    } label: {
                        Text(speedLabel(speed))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selected ? Theme.accentInk : Theme.textSubtle)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? Theme.accent : Theme.surface)
                            )
                    }
                }
            }
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
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    // MARK: - Sleep timer

    private var sleepSection: some View {
        card(title: "Sleep Timer", systemImage: "moon.zzz.fill") {
            if let endsAt = player.sleepTimerEndsAt {
                VStack(spacing: 12) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, endsAt.timeIntervalSince(context.date))
                        Text("Pausing in \(remaining.mmssString)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.accent)
                            .monospacedDigit()
                    }
                    Button {
                        player.cancelSleepTimer()
                    } label: {
                        Text("Cancel Timer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red.opacity(0.9))
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(sleepPresets, id: \.self) { minutes in
                            let selected = Int(sleepMinutes) == minutes
                            Button {
                                sleepMinutes = Double(minutes)
                            } label: {
                                Text("\(minutes)m")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selected ? Theme.accentInk : Theme.textSubtle)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(selected ? Theme.accent : Theme.surface)
                                    )
                            }
                        }
                    }
                    PrimaryButton(title: "Start Timer") {
                        player.setSleepTimer(minutes: Int(sleepMinutes))
                    }
                }
            }
        }
    }

    // MARK: - Card

    private func card(title: String, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .emberCard(cornerRadius: 16)
    }
}

#Preview {
    AdvancedControlsSheet()
        .environmentObject(AudioPlayerManager())
}
