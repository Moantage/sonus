import SwiftUI

/// Single source of truth for Sonus' "Paper" look — a warm, editorial, print-inspired
/// aesthetic: cream paper backgrounds, ink-black type, a single terracotta accent,
/// serif display headlines and monospaced micro-labels (Novora Labs branding).
///
/// Restyle only: every screen, state, and component API is unchanged. Views read
/// colors and fonts from here rather than hardcoding them. All symbol names are kept
/// stable so the whole app adopts the new look at once.
enum Theme {
    // MARK: Backgrounds
    /// Warm paper base fill (the screen).
    static let backgroundBase = Color(hex: 0xF2E9DB)
    /// Tab bar / mini-player / raised chrome.
    static let backgroundElevated = Color(hex: 0xECE0CB)

    // Legacy gradient stops kept as paper tones so any older references still read on-brand.
    static let backgroundTop = Color(hex: 0xF2E9DB)
    static let backgroundMid = Color(hex: 0xECE0CB)
    static let backgroundBottom = Color(hex: 0xE7DDC9)

    // MARK: Surfaces & borders
    /// Cards, rows, fields (opaque warm sand).
    static let surface = Color(hex: 0xE9DCC6)
    /// Selected row, chips, icon wells.
    static let surfaceRaised = Color(hex: 0xECE0CB)
    /// 1px hairline strokes on all cards / dividers.
    static let hairline = Color(hex: 0x1C1613).opacity(0.12)
    /// Back-compat alias used by a few older views.
    static let card = Color(hex: 0xE9DCC6)

    // MARK: Text (ink on paper)
    /// Ink-black primary text.
    static let textPrimary = Color(hex: 0x1C1613)
    /// Secondary / captions (warm taupe).
    static let textSubtle = Color(hex: 0x6F6252)
    /// Back-compat alias.
    static let subtleText = Color(hex: 0x6F6252)
    /// Muted mono micro-label ink.
    static let textMuted = Color(hex: 0xA8987F)

    // MARK: Accent (terracotta)
    static let accent = Color(hex: 0xB5432E)
    static let accentLight = Color(hex: 0xC96A4F)
    static let accentDeep = Color(hex: 0x8F3020)
    /// Text / glyphs ON dark (ink) or accent fills — warm cream.
    static let accentInk = Color(hex: 0xF2E9DB)

    /// Ink — the near-black used for primary buttons and the play control.
    static let ink = Color(hex: 0x1C1613)

    // MARK: Premium / status
    static let premiumGold = Color(hex: 0xB5432E)
    static let premiumGoldWell = Color(hex: 0xB5432E).opacity(0.12)
    static let error = Color.red.opacity(0.9)

    // MARK: Typography helpers
    /// DM Serif Display stand-in — native New York serif for display headlines.
    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Space Mono stand-in — native monospaced for eyebrows / micro-labels.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Gradients
    /// Warm album-art / avatar placeholder gradient (vermillion).
    static var artworkGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xE8590C), Color(hex: 0xB7261D)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Solid ink "gradient" for the primary play/pause button.
    static var playGradient: LinearGradient {
        LinearGradient(colors: [ink, ink], startPoint: .top, endPoint: .bottom)
    }

    /// Flat warm-paper app background.
    static var background: some View {
        backgroundBase.ignoresSafeArea()
    }

    /// Now Playing screen background — flat warm paper.
    static var playerBackground: some View {
        backgroundBase.ignoresSafeArea()
    }
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

// MARK: - Brand mark (Sonus — editorial waveform)

/// The Sonus mark: five vertical bars, center-tallest, in ink with a terracotta
/// center — a restrained, print-shop take on the equalizer glyph. Scales to any size.
struct WaveformMark: View {
    var size: CGFloat = 88
    var color: Color = Theme.ink

    // On an 88×88 grid: bars 8 wide, x = 12/28/44/60/76, heights 22/44/62/38/20.
    private let bars: [(x: CGFloat, h: CGFloat, accent: Bool)] = [
        (12, 22, false), (28, 44, false), (44, 62, true), (60, 38, false), (76, 20, false)
    ]

    var body: some View {
        let unit = size / 88
        ZStack {
            ForEach(bars.indices, id: \.self) { i in
                let bar = bars[i]
                RoundedRectangle(cornerRadius: 1 * unit, style: .continuous)
                    .fill(bar.accent ? Theme.accent : color)
                    .frame(width: 8 * unit, height: bar.h * unit)
                    .position(x: (bar.x + 4) * unit, y: size / 2)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Waveform mark seated on a paper tile with a hairline border — used on Login,
/// Onboarding, and the app-icon lockup.
struct BrandLogoTile: View {
    var size: CGFloat = 88

    var body: some View {
        WaveformMark(size: size * 0.62, color: Theme.ink)
            .frame(width: size, height: size)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Reusable card / border modifiers

extension View {
    /// Surface card with hairline border. Editorial radius is near-square (2pt default).
    func emberCard(cornerRadius: CGFloat = 2, fill: Color = Theme.surface) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(Theme.mono(11, weight: .regular))
                .tracking(1.4)
                .foregroundColor(Theme.accent)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .textContentType(contentType)
            .font(.system(size: 16))
            .foregroundColor(Theme.textPrimary)
            .padding(14)
            .emberCard(cornerRadius: 2)
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
                    Text(title.uppercased())
                        .font(Theme.mono(13, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(Theme.accentInk)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Theme.ink.opacity(isDisabled ? 0.4 : 1),
                in: RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
        }
        .disabled(isDisabled || isLoading)
    }
}

struct InlineError: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(Theme.error)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
