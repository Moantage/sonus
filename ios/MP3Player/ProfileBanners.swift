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
        colors: [Color(hex: 0x6B4A22), Color(hex: 0x231D14)])

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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ProfileBanner.all) { banner in
                            bannerCell(banner)
                        }
                    }

                    if !isPremium {
                        Label("Classic is free. The others come with Sonus Premium.", systemImage: "crown.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSubtle)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.backgroundElevated)
            .navigationTitle("Profile banner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.backgroundElevated)
        .presentationCornerRadius(20)
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
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(banner.gradient)
                    .frame(height: 88)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Text(banner.name)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .stroke(selected ? Theme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(banner.name)
        .accessibilityValue(selected ? "Selected" : (locked ? "Premium" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
