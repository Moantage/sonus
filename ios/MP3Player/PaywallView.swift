import SwiftUI
import StoreKit

/// Premium upgrade paywall: a Standard vs Premium comparison plus the two
/// purchase options (€3/month subscription or €11 lifetime). Styled to match
/// the app's dark theme.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var purchasing = false
    @State private var errorMessage: String?

    // Feature comparison rows. `standard` nil = not included (shown as —/✗).
    private struct Feature {
        let name: String
        let standard: String?
        let premium: String
    }

    private let features: [Feature] = [
        Feature(name: "Ad-free listening",        standard: nil,          premium: "Included"),
        Feature(name: "Audio quality",            standard: "Standard",   premium: "High quality"),
        Feature(name: "Advanced audio controls",  standard: nil,          premium: "Included"),
        Feature(name: "Premium profile banners",  standard: nil,          premium: "Included"),
        Feature(name: "Cloud library sync",       standard: nil,          premium: "Any device"),
        Feature(name: "Offline downloads",        standard: nil,          premium: "Any device")
    ]

    var body: some View {
        ZStack {
            Theme.background

            ScrollView(showsIndicators: false) {
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

            closeButton
        }
        .preferredColorScheme(.light)
        .onChange(of: store.isPremium) { _, isPremium in
            if isPremium { dismiss() }   // unlocked — close the paywall
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.artworkGradient)
                    .frame(width: 72, height: 72)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 18)
                Image(systemName: "crown.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.accentInk)
            }

            Text("Go Premium")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text("Unlock the best of Sonus — no ads, higher quality, and your library everywhere.")
                .font(.system(size: 15))
                .foregroundColor(Theme.textSubtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.top, 24)
    }

    // MARK: - Comparison table

    private var comparisonCard: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("Features")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.subtleText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Standard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSubtle)
                    .frame(width: 78)

                Text("Premium")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.accentInk)
                    .frame(width: 92)
                    .padding(.vertical, 6)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                Divider().background(Theme.hairline)
                row(feature)
                    .background(index.isMultiple(of: 2) ? Theme.ink.opacity(0.03) : .clear)
            }
        }
        .emberCard(cornerRadius: 16)
    }

    private func row(_ feature: Feature) -> some View {
        HStack(spacing: 0) {
            Text(feature.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Standard column
            Group {
                if let value = feature.standard {
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.subtleText)
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.subtleText.opacity(0.5))
                }
            }
            .frame(width: 78)

            // Premium column
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.accent)
                Text(feature.premium)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 92)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Purchase buttons

    private var purchaseButtons: some View {
        VStack(spacing: 12) {
            // Lifetime — highlighted as best value
            planButton(
                title: "Lifetime",
                subtitle: "One-time payment · yours forever",
                price: store.lifetime?.displayPrice ?? "€11",
                cadence: nil,
                highlighted: true,
                badge: "Best value"
            ) {
                if let product = store.lifetime { buy(product) }
            }

            // Monthly subscription
            planButton(
                title: "Monthly",
                subtitle: "Auto-renews · cancel anytime",
                price: store.monthly?.displayPrice ?? "€3",
                cadence: "/mo",
                highlighted: false,
                badge: nil
            ) {
                if let product = store.monthly { buy(product) }
            }

            Button("Restore Purchases") {
                Task { await store.restore() }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Theme.accent)
            .padding(.top, 4)
            .disabled(purchasing)
        }
    }

    private func planButton(
        title: String,
        subtitle: String,
        price: String,
        cadence: String?,
        highlighted: Bool,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                        if let badge {
                            Text(badge.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Theme.accentInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.accent))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSubtle)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(price)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    if let cadence {
                        Text(cadence)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textSubtle)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(highlighted
                          ? AnyShapeStyle(Theme.accent.opacity(0.14))
                          : AnyShapeStyle(Theme.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(highlighted ? Theme.accent.opacity(0.6) : Theme.hairline,
                            lineWidth: highlighted ? 1.5 : 1)
            )
        }
        .disabled(purchasing)
        .opacity(purchasing ? 0.6 : 1)
    }

    // MARK: - Footer / legal

    private var footer: some View {
        VStack(spacing: 10) {
            if purchasing {
                ProgressView().tint(Theme.accent)
            }

            Text("The Monthly plan is an auto-renewable subscription. Payment is charged to your Apple ID, and it renews automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel anytime in your App Store account settings. Lifetime is a one-time purchase.")
                .font(.system(size: 11))
                .foregroundColor(Theme.subtleText.opacity(0.8))
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Link("Terms", destination: ConsentConfig.termsURL)
                Text("·").foregroundColor(Theme.subtleText)
                Link("Privacy", destination: ConsentConfig.privacyURL)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .padding(10)
                        .background(Circle().fill(Theme.surfaceRaised))
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                }
            }
            Spacer()
        }
        .padding(16)
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
