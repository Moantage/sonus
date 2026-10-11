import SwiftUI

/// Three-page minimal onboarding, shown once before login.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0

    private let pages: [(icon: String, title: String, subtitle: String)] = [
        ("music.note", "Your music, beautifully simple",
         "Import your MP3s and play them anywhere — no clutter, no noise."),
        ("waveform", "Built for listening",
         "Background playback, a clean library, and controls that stay out of your way."),
        ("lock.shield", "Private by design",
         "Sign in your way — Apple, Google, email, or phone. Your data stays yours.")
    ]

    var body: some View {
        ZStack {
            Theme.background

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.subtleText)
                        .padding(24)
                }

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        VStack(spacing: 24) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(Theme.artworkGradient)
                                    .frame(width: 96, height: 96)
                                    .shadow(color: Theme.accent.opacity(0.4), radius: 24)
                                Image(systemName: pages[index].icon)
                                    .font(.system(size: 44, weight: .semibold))
                                    .foregroundColor(Theme.accentInk)
                            }
                            .frame(height: 100)

                            Text(pages[index].title)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(Theme.textPrimary)
                                .multilineTextAlignment(.center)

                            Text(pages[index].subtitle)
                                .font(.system(size: 16))
                                .foregroundColor(Theme.textSubtle)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 40)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Page dots
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.accent : Color.white.opacity(0.2))
                            .frame(width: index == page ? 26 : 7, height: 7)
                            .animation(.spring(duration: 0.3), value: page)
                    }
                }
                .padding(.bottom, 32)

                PrimaryButton(title: page == pages.count - 1 ? "Get Started" : "Continue") {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        finish()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.light)
    }

    private func finish() {
        withAnimation { hasCompletedOnboarding = true }
    }
}

#Preview {
    OnboardingView()
}
