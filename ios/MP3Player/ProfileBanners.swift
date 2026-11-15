import SwiftUI

/// Selectable profile header banners. All of them are free.
struct ProfileBanner: Identifiable, Hashable {
    let id: String
    let name: String
    let colors: [Color]

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let classic = ProfileBanner(
        id: "classic", name: "Classic",
        colors: [Color(hex: 0x6B4A22), Color(hex: 0x231D14)])

    static let aurora = ProfileBanner(
        id: "aurora", name: "Aurora",
        colors: [Color(red: 0.20, green: 0.45, blue: 0.95), Color(red: 0.45, green: 0.30, blue: 0.85), Color(red: 0.15, green: 0.65, blue: 0.70)])

    static let sunset = ProfileBanner(
        id: "sunset", name: "Sunset",
        colors: [Color(red: 0.98, green: 0.45, blue: 0.30), Color(red: 0.90, green: 0.25, blue: 0.55), Color(red: 0.45, green: 0.20, blue: 0.65)])

    static let ocean = ProfileBanner(
        id: "ocean", name: "Ocean",
        colors: [Color(red: 0.10, green: 0.55, blue: 0.65), Color(red: 0.10, green: 0.35, blue: 0.70), Color(red: 0.06, green: 0.16, blue: 0.42)])

    static let nebula = ProfileBanner(
        id: "nebula", name: "Nebula",
        colors: [Color(red: 0.45, green: 0.20, blue: 0.75), Color(red: 0.80, green: 0.25, blue: 0.70), Color(red: 0.25, green: 0.20, blue: 0.55)])

    static let graphite = ProfileBanner(
        id: "graphite", name: "Graphite",
        colors: [Color(red: 0.22, green: 0.24, blue: 0.30), Color(red: 0.10, green: 0.11, blue: 0.15)])

    static let all: [ProfileBanner] = [classic, aurora, sunset, ocean, nebula, graphite]

    static func banner(for id: String?) -> ProfileBanner {
        all.first { $0.id == id } ?? classic
    }

    // Convenience init so the static declarations read cleanly.
    private init(id: String, name: String, colors: [Color]) {
        self.id = id
        self.name = name
        self.colors = colors
    }
}

/// Grid to pick a profile banner.
struct BannerPickerSheet: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        CompatNavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ProfileBanner.all) { banner in
                        bannerCell(banner)
                    }
                }
                .padding(20)
            }
            .background(Theme.backgroundElevated)
            .navigationTitle("Profile banner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .emberSheet(background: Theme.backgroundElevated, cornerRadius: 20)
    }

    private func bannerCell(_ banner: ProfileBanner) -> some View {
        let selected = ProfileBanner.banner(for: authManager.currentUser?.profileBanner).id == banner.id
        return Button {
            Task { await authManager.updateProfileBanner(banner.id) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(banner.gradient)
                    .frame(height: 88)

                HStack {
                    Text(banner.name)
                        .font(.system(.footnote).weight(.bold))
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
        .haptic(.selection, trigger: selected)
        .accessibilityLabel(banner.name)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
