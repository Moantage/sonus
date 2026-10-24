import SwiftUI

/// Single source of truth for Sonus' **Ember** look: warm near-black graphite, one amber
/// accent, bold SF Pro type, pill-shaped buttons and chips, small artwork corners.
///
/// Ember owns colour and brand; layout and interaction follow the zero-learning-curve
/// music-app conventions (tabs, mini-player, slide-up Now Playing). The app is dark only.
/// Views read colours, type and shapes from here instead of hardcoding them.
enum Theme {
    // MARK: Backgrounds

    /// Warm ink. The base fill of every screen.
    static let backgroundBase = Color(hex: 0x14110E)
    /// Raised chrome: sheets, the tab bar, cards that sit on the base.
    static let backgroundElevated = Color(hex: 0x231D14)
    /// Highest layer: menus and the bottom sheets' rows on press.
    static let backgroundHighlight = Color(hex: 0x2E261B)

    // MARK: Surfaces & borders

    /// Cards, rows, fields.
    static let surface = Color.white.opacity(0.06)
    /// Selected rows, chips, icon wells.
    static let surfaceRaised = Color.white.opacity(0.11)
    /// 1px strokes, used sparingly (outlined buttons, dividers).
    static let hairline = Color.white.opacity(0.10)
    /// Outline for secondary pill buttons.
    static let outline = Color(hex: 0xF3EEE6).opacity(0.38)

    // MARK: Text

    /// Warm cream.
    static let textPrimary = Color(hex: 0xF3EEE6)
    /// Secondary text and captions.
    static let textSubtle = Color(hex: 0xF3EEE6).opacity(0.62)
    /// Tertiary text, disabled glyphs.
    static let textMuted = Color(hex: 0xF3EEE6).opacity(0.38)

    // MARK: Accent (amber)

    static let accent = Color(hex: 0xE8B15E)
    static let accentLight = Color(hex: 0xF0C77E)
    static let accentDeep = Color(hex: 0xC98F3E)
    /// Text and glyphs on amber fills.
    static let accentInk = Color(hex: 0x1A1206)

    // MARK: Premium / status

    static let premiumGold = Color(hex: 0xFFD60A)
    static let premiumGoldWell = Color(hex: 0xFFD60A).opacity(0.14)
    static let error = Color.red.opacity(0.9)
    static let success = Color(hex: 0x7FD6A0)

    // MARK: Shape

    enum Radius {
        /// Song and playlist artwork.
        static let artwork: CGFloat = 10
        /// Cards, the mini-player, fields.
        static let card: CGFloat = 14
        /// Larger tiles (Home shortcuts, banners).
        static let tile: CGFloat = 20
        /// The hero artwork on Now Playing and collection pages.
        static let hero: CGFloat = 16
    }

    // MARK: Motion

    /// One spring vocabulary, so every surface moves the same way.
    enum Motion {
        /// Taps, toggles, small state changes.
        static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
        /// Surfaces that travel: the player expanding, cards sliding.
        static let glide = Animation.spring(response: 0.48, dampingFraction: 0.86)
        /// Elastic returns after a drag.
        static let bounce = Animation.spring(response: 0.38, dampingFraction: 0.68)
    }

    // MARK: Gradients

    /// Album-art / avatar placeholder gradient (Ember handoff: 150°, amber → copper).
    static var artworkGradient: LinearGradient {
        LinearGradient(
            colors: [accent, Color(hex: 0xC77D4A)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The big play button's fill.
    static var playGradient: LinearGradient {
        LinearGradient(colors: [accentLight, accent, accentDeep], startPoint: .top, endPoint: .bottom)
    }

    /// Flat warm-ink app background.
    static var background: some View {
        backgroundBase.ignoresSafeArea()
    }

    /// Top-lit warm glow used behind onboarding, login and the paywall.
    static var glowBackground: some View {
        ZStack {
            backgroundBase
            RadialGradient(
                colors: [Color(hex: 0x2B2113), backgroundBase],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Typography

/// Bold SF Pro, mapped to Dynamic Type text styles so every screen scales.
extension Font {
    /// Page titles ("Your Library", "Search").
    static let emberPageTitle = Font.system(.title2, weight: .bold)
    /// Big hero titles (playlist header, Now Playing title).
    static let emberHero = Font.system(.title, weight: .bold)
    /// Section headings on Home.
    static let emberSection = Font.system(.title3, weight: .bold)
    /// Row titles.
    static let emberRowTitle = Font.system(.body, weight: .medium)
    /// Row subtitles and captions.
    static let emberRowSubtitle = Font.system(.subheadline)
    /// Labels on pill buttons.
    static let emberButton = Font.system(.callout, weight: .bold)
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Brand mark (locked: Waveform)

/// The Sonus mark: five amber bars, centre tallest, opacities 0.5 / 0.75 / 1 / 0.75 / 0.5.
/// Drawn on an 88×88 grid (bars 10 wide, radius 5) and scaled to any size.
struct WaveformMark: View {
    var size: CGFloat = 88
    var color: Color = Theme.accent

    private struct Bar {
        let x: CGFloat
        let height: CGFloat
        let opacity: Double
    }

    private let bars: [Bar] = [
        Bar(x: 10, height: 24, opacity: 0.5),
        Bar(x: 26, height: 46, opacity: 0.75),
        Bar(x: 42, height: 64, opacity: 1),
        Bar(x: 58, height: 36, opacity: 0.75),
        Bar(x: 74, height: 18, opacity: 0.5)
    ]

    var body: some View {
        let unit = size / 88
        ZStack {
            ForEach(bars.indices, id: \.self) { index in
                let bar = bars[index]
                RoundedRectangle(cornerRadius: 5 * unit, style: .continuous)
                    .fill(color.opacity(bar.opacity))
                    .frame(width: 10 * unit, height: bar.height * unit)
                    .position(x: (bar.x + 5) * unit, y: size / 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The mark on its warm graphite tile, as on the app icon. Used on Login and Onboarding.
struct BrandLogoTile: View {
    var size: CGFloat = 88

    var body: some View {
        WaveformMark(size: size * 0.66)
            .frame(width: size, height: size)
            .background(
                RadialGradient(
                    colors: [Color(hex: 0x241D12), Theme.backgroundBase],
                    center: .top,
                    startRadius: 0,
                    endRadius: size
                ),
                in: RoundedRectangle(cornerRadius: size * 26 / 88, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 26 / 88, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: Theme.accent.opacity(0.22), radius: size * 0.3)
            .accessibilityHidden(true)
    }
}

// MARK: - Card modifier

extension View {
    /// Surface card. Borders are opt-in: most cards rely on fill alone.
    func emberCard(
        cornerRadius: CGFloat = Theme.Radius.card,
        fill: Color = Theme.surface,
        bordered: Bool = false
    ) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                }
            }
    }
}

// MARK: - Button styles

/// Shrinks slightly while pressed, then springs back. The default for tappable cards and
/// icon buttons.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Full-width pill button.
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        /// Amber fill, ink label.
        case primary
        /// Cream fill, ink label (e.g. the white "Continue with Apple" look).
        case light
        /// Transparent with a cream outline.
        case outline
        /// Quiet surface fill.
        case surface
    }

    var kind: Kind = .primary
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.emberButton)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 20)
            .background(background, in: Capsule())
            .overlay {
                if kind == .outline {
                    Capsule().stroke(Theme.outline, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .light: return Theme.accentInk
        case .outline, .surface: return Theme.textPrimary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.accent
        case .light: return Theme.textPrimary
        case .outline: return .clear
        case .surface: return Theme.surfaceRaised
        }
    }
}

// MARK: - Shared components

struct ThemedField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false
    var contentType: UITextContentType?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .focused($isFocused)
            .textContentType(contentType)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(isFocused ? Theme.accent : .clear, lineWidth: 1.5)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(Theme.accentInk)
                } else {
                    Text(title)
                }
            }
        }
        .buttonStyle(PillButtonStyle(kind: .primary, isEnabled: !isDisabled))
        .disabled(isDisabled || isLoading)
    }
}

struct InlineError: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.error)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// Horizontal filter chip ("Playlists", "Downloaded"). Selected = amber fill, ink label.
struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(isSelected ? Theme.accentInk : Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(isSelected ? Theme.accent : Theme.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Round initials avatar, used top-left on every tab and on the profile header.
struct AvatarView: View {
    let initials: String
    var size: CGFloat = 32

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(Theme.accentInk)
            .frame(width: size, height: size)
            .background(Theme.artworkGradient, in: Circle())
    }
}

/// Section heading with an optional trailing action, Home-style.
struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.emberSection)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textSubtle)
            }
        }
    }
}
