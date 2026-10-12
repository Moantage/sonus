import SwiftUI

// MARK: - Settings building blocks

/// A bold section title over plain rows.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.emberSection)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

struct SettingsLabel: View {
    let icon: String
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.textSubtle)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSubtle)
                }
            }
            .multilineTextAlignment(.leading)
        }
    }
}

/// A tappable settings row with a chevron, or a lock for Premium features.
struct SettingsRow: View {
    let icon: String
    let title: String
    var detail: String?
    var isLocked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsLabel(icon: icon, title: title, detail: detail)
                Spacer(minLength: 0)
                Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isLocked ? Theme.accent : Theme.textMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityValue(isLocked ? "Premium" : "")
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.textSubtle)
            Spacer(minLength: 8)
            Text(value)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
