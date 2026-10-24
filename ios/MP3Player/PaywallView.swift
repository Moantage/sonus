import SwiftUI
import StoreKit

/// Premium upgrade paywall: what's free with an account vs. what Premium adds, plus the two
/// purchase options (€3/month subscription or €11 lifetime).
///
/// Free with an account: your sources, streaming and offline downloads. Premium: high-quality
/// audio, profile banners, sync across devices, and ad-free listening while ads exist.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var purchasing = false
    @State private var errorMessage: String?

    private struct Feature: Identifiable {
        let name: String
        let icon: String
        let isFree: Bool

        var id: String { name }
    }

    private let features: [Feature] = [
        Feature(name: "Your music sources", icon: "externaldrive.connected.to.line.below", isFree: true),
        Feature(name: "Streaming", icon: "dot.radiowaves.left.and.right", isFree: true),
        Feature(name: "Offline downloads", icon: "arrow.down.circle", isFree: true),
        Feature(name: "High-quality audio", icon: "waveform", isFree: false),
        Feature(name: "Profile banners", icon: "photo", isFree: false),
        Feature(name: "Sync across devices", icon: "arrow.triangle.2.circlepath", isFree: false),
        Feature(name: "Ad-free listening", icon: "speaker.slash", isFree: false)
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.glowBackground

            ScrollView {
                VStack(spacing: 24) {
                    header
                    comparisonCard
                    purchaseButtons

                    if let errorMessage {
                        InlineError(message: errorMessage)
                            .padding(.horizontal, 4)
                    }

                    footer
                }
                .padding(20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)

            closeButton
        }
        .presentationBackground(Theme.backgroundBase)
        .onChange(of: store.isPremium) { _, isPremium in
            if isPremium { dismiss() }   // unlocked — close the paywall
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 72, height: 72)
                .background(Theme.playGradient, in: Circle())
                .shadow(color: Theme.accent.opacity(0.4), radius: 18)
                .accessibilityHidden(true)

            Text("Go Premium")
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("Make Sonus yours: high-quality audio, profile banners, your library on every device, and no ads.")
                .font(.body)
                .foregroundStyle(Theme.textSubtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.top, 24)
    }

    // MARK: - Comparison table

    private var comparisonCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Your account")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textSubtle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Free")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textSubtle)
                    .frame(width: 64)

                Text("Premium")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 84)
                    .padding(.vertical, 6)
                    .background(Theme.accent, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .accessibilityHidden(true)

            ForEach(features) { feature in
                Rectangle().fill(Theme.hairline).frame(height: 1)
                row(feature)
            }
        }
        .emberCard(cornerRadius: Theme.Radius.tile)
    }

    private func row(_ feature: Feature) -> some View {
        HStack(spacing: 0) {
            Label {
                Text(feature.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: feature.icon)
                    .foregroundStyle(Theme.textSubtle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if feature.isFree {
                    Image(systemName: "checkmark")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Image(systemName: "minus")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(width: 64)

            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 84)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feature.name)
        .accessibilityValue(feature.isFree ? "Free with your account" : "Premium")
    }

    // MARK: - Purchase buttons

    private var purchaseButtons: some View {
        VStack(spacing: 12) {
            planButton(
                PlanStyle(
                    title: "Lifetime",
                    subtitle: "One-time payment · yours forever",
                    price: store.lifetime?.displayPrice ?? "€11",
                    cadence: nil,
                    badge: "Best value"
                )
            ) {
                if let product = store.lifetime { buy(product) }
            }

            planButton(
                PlanStyle(
                    title: "Monthly",
                    subtitle: "Auto-renews · cancel anytime",
                    price: store.monthly?.displayPrice ?? "€3",
                    cadence: "/mo",
                    badge: nil
                )
            ) {
                if let product = store.monthly { buy(product) }
            }

            Button("Restore purchases") {
                Task { await store.restore() }
            }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(minHeight: 44)
            .disabled(purchasing)
        }
    }

    private struct PlanStyle {
        let title: String
        let subtitle: String
        let price: String
        let cadence: String?
        /// Highlighted plans carry a badge ("Best value").
        let badge: String?
    }

    private func planButton(_ plan: PlanStyle, action: @escaping () -> Void) -> some View {
        let highlighted = plan.badge != nil
        return Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(.headline, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(.caption2, weight: .bold))
                                .foregroundStyle(Theme.accentInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                    Text(plan.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSubtle)
                }
                .multilineTextAlignment(.leading)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(plan.price)
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if let cadence = plan.cadence {
                        Text(cadence)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSubtle)
                    }
                }
            }
            .padding(18)
            .background(
                highlighted ? Theme.accent.opacity(0.14) : Theme.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .stroke(highlighted ? Theme.accent.opacity(0.7) : Theme.hairline, lineWidth: highlighted ? 1.5 : 1)
            )
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .disabled(purchasing)
        .opacity(purchasing ? 0.6 : 1)
    }

    // MARK: - Footer / legal

    private var footer: some View {
        VStack(spacing: 10) {
            if purchasing {
                ProgressView().tint(Theme.accent)
            }

            Text(
                "The Monthly plan is an auto-renewable subscription. Payment is charged to your Apple ID, and it renews "
                    + "automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel "
                    + "anytime in your App Store account settings. Lifetime is a one-time purchase."
            )
            .font(.caption2)
            .foregroundStyle(Theme.textMuted)
            .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Link("Terms", destination: ConsentConfig.termsURL)
                Text("·").foregroundStyle(Theme.textSubtle)
                Link("Privacy", destination: ConsentConfig.privacyURL)
            }
            .font(.system(.caption, weight: .semibold))
        }
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(Theme.surfaceRaised, in: Circle())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Close")
        .padding(12)
    }

    // MARK: - Actions

    private func buy(_ product: Product) {
        errorMessage = nil
        purchasing = true
        Task {
            let outcome = await store.purchase(product)
            purchasing = false
            switch outcome {
            case .success:
                dismiss()
            case .pending:
                errorMessage = "Your purchase is pending approval. You'll get access once it's approved."
            case .cancelled:
                break
            case .failed:
                errorMessage = store.lastError ?? "The purchase couldn't be completed. Please try again."
            }
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(StoreManager.shared)
}
