import SwiftUI

/// Three-page onboarding, shown once before login.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let subtitle: String
    }

    private let pages: [Page] = [
        Page(
            icon: "music.note",
            title: "Your music, beautifully simple",
            subtitle: "Bring in the songs you own and play them anywhere. No clutter, no noise."
        ),
        Page(
            icon: "waveform",
            title: "Built for listening",
            subtitle: "Background playback, a clean library, and controls that stay out of your way."
        ),
        Page(
            icon: "lock.shield",
            title: "Private by design",
            subtitle: "Sign in your way: Apple, Google, email or phone. Your data stays yours."
        )
    ]

    var body: some View {
        ZStack {
            Theme.glowBackground

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textSubtle)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 16)
                }

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(pages[index], isFirst: index == 0)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.accent : Theme.textPrimary.opacity(0.2))
                            .frame(width: index == page ? 26 : 7, height: 7)
                            .animation(.spring(duration: 0.3), value: page)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(page + 1) of \(pages.count)")
                .padding(.bottom, 32)

                PrimaryButton(title: page == pages.count - 1 ? "Get started" : "Continue") {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        finish()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    private func pageView(_ page: Page, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            if isFirst {
                BrandLogoTile(size: 88)
            } else {
                Image(systemName: page.icon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 88, height: 88)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityHidden(true)
            }

            Text(page.title)
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(page.subtitle)
                .font(.body)
                .foregroundStyle(Theme.textSubtle)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
    }

    private func finish() {
        withAnimation { hasCompletedOnboarding = true }
    }
}

#Preview {
    OnboardingView()
}
