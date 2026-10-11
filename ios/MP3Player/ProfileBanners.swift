import SwiftUI

/// Selectable profile header banners. "Classic" is free; the rest are premium.
struct ProfileBanner: Identifiable, Hashable {
    let id: String
    let name: String
    let colors: [Color]
    let isPremium: Bool

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let classic = ProfileBanner(
        id: "classic", name: "Classic", isPremiumInit: false,
        colors: [Color(hex: 0x2B2113), Color(hex: 0x14110E)])

    static let aurora = ProfileBanner(
        id: "aurora", name: "Aurora", isPremiumInit: true,
        colors: [Color(red: 0.20, green: 0.45, blue: 0.95), Color(red: 0.45, green: 0.30, blue: 0.85), Color(red: 0.15, green: 0.65, blue: 0.70)])

    static let sunset = ProfileBanner(
        id: "sunset", name: "Sunset", isPremiumInit: true,
        colors: [Color(red: 0.98, green: 0.45, blue: 0.30), Color(red: 0.90, green: 0.25, blue: 0.55), Color(red: 0.45, green: 0.20, blue: 0.65)])

    static let ocean = ProfileBanner(
        id: "ocean", name: "Ocean", isPremiumInit: true,
        colors: [Color(red: 0.10, green: 0.55, blue: 0.65), Color(red: 0.10, green: 0.35, blue: 0.70), Color(red: 0.06, green: 0.16, blue: 0.42)])

    static let nebula = ProfileBanner(
        id: "nebula", name: "Nebula", isPremiumInit: true,
        colors: [Color(red: 0.45, green: 0.20, blue: 0.75), Color(red: 0.80, green: 0.25, blue: 0.70), Color(red: 0.25, green: 0.20, blue: 0.55)])

    static let graphite = ProfileBanner(
        id: "graphite", name: "Graphite", isPremiumInit: true,
        colors: [Color(red: 0.22, green: 0.24, blue: 0.30), Color(red: 0.10, green: 0.11, blue: 0.15)])

    static let all: [ProfileBanner] = [classic, aurora, sunset, ocean, nebula, graphite]

    static func banner(for id: String?) -> ProfileBanner {
        all.first { $0.id == id } ?? classic
    }

    // Convenience init so the static declarations read cleanly.
    private init(id: String, name: String, isPremiumInit: Bool, colors: [Color]) {
        self.id = id
        self.name = name
        self.isPremium = isPremiumInit
        self.colors = colors
    }
}

/// Premium-gated grid to pick a profile banner.
struct BannerPickerSheet: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    let isPremium: Bool
    var onNeedsUpgrade: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ProfileBanner.all) { banner in
                            bannerCell(banner)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Profile Banner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func bannerCell(_ banner: ProfileBanner) -> some View {
        let selected = ProfileBanner.banner(for: authManager.currentUser?.profileBanner).id == banner.id
        let locked = banner.isPremium && !isPremium

        return Button {
            if locked {
                onNeedsUpgrade()
            } else {
                Task { await authManager.updateProfileBanner(banner.id) }
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(banner.gradient)
                    .frame(height: 84)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Text(banner.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.accent)
                    }
                }
                .padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Theme.accent : Theme.hairline,
                            lineWidth: selected ? 2 : 1)
            )
        }
    }
}
