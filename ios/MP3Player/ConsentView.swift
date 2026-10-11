import SwiftUI

/// Versioned agreement config. Bump `currentVersion` whenever the terms change
/// materially — users will be re-prompted to accept on next launch.
enum ConsentConfig {
    static let currentVersion = "1.0"
    static let lastUpdated = "2 July 2026"

    // TODO: replace with your real published URLs and company details.
    static let termsURL = URL(string: "https://example.com/terms")!
    static let privacyURL = URL(string: "https://example.com/privacy")!
    static let controllerName = "Novora Labs"           // your company / legal name
    static let contactEmail = "privacy@example.com"     // your data-protection contact
}

/// First-run GDPR agreement gate. Shown after sign-in until the user has
/// actively accepted the current agreement version. Acceptance is recorded
/// in Firestore with a server timestamp.
struct ConsentView: View {
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var agreed = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Theme.surfaceRaised)
                            .frame(width: 72, height: 72)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Theme.hairline, lineWidth: 1)
                            )
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundColor(Theme.accent)
                    }
                    Text("Your privacy")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Please review and accept before you continue.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSubtle)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                .padding(.bottom, 20)
                .padding(.horizontal, 24)

                // Agreement body
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Self.sections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Theme.textPrimary)
                                Text(section.body)
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textSubtle)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(spacing: 6) {
                            Link("Full Terms of Service", destination: ConsentConfig.termsURL)
                            Text("·").foregroundColor(Theme.subtleText)
                            Link("Full Privacy Policy", destination: ConsentConfig.privacyURL)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.top, 4)

                        Text("Version \(ConsentConfig.currentVersion) · Last updated \(ConsentConfig.lastUpdated)")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.subtleText.opacity(0.7))
                    }
                    .padding(20)
                    .emberCard(cornerRadius: 18)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                // Accept
                VStack(spacing: 14) {
                    Button {
                        agreed.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                .font(.system(size: 22))
                                .foregroundColor(agreed ? Theme.accent : Theme.textSubtle)
                            Text("I have read and agree to the Terms of Service and Privacy Policy, and I consent to the processing of my personal data as described above.")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }

                    if let errorMessage {
                        InlineError(message: errorMessage)
                    }

                    PrimaryButton(title: "Agree & Continue",
                                  isLoading: isSaving,
                                  isDisabled: !agreed) {
                        accept()
                    }

                    Button("Decline and sign out") {
                        authManager.signOut()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.subtleText)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.light)
    }

    private func accept() {
        guard agreed else { return }
        errorMessage = nil
        isSaving = true
        Task {
            let error = await authManager.recordConsent()
            isSaving = false
            if error != nil {
                errorMessage = "Couldn't save your response. Check your connection and try again."
            }
            // On success, `needsConsent` flips false and the app routes onward.
        }
    }

    // MARK: - Agreement content
    //
    // ⚠️ This is a solid, GDPR-structured starting point — NOT a substitute for
    // legal review. Fill in ConsentConfig with your real company details and
    // have a lawyer confirm it fits your jurisdiction and data practices.

    private struct Section { let title: String; let body: String }

    private static let sections: [Section] = [
        Section(
            title: "Who is responsible for your data",
            body: "\(ConsentConfig.controllerName) is the data controller for the personal information processed in this app. For any privacy question or to exercise your rights, contact us at \(ConsentConfig.contactEmail)."
        ),
        Section(
            title: "What we collect",
            body: "Your name and email address; a one-way hashed version of your phone number (plus the last 4 digits) if you add one; your sign-in method (Apple, Google, email, or phone); your account and subscription status; and, if you use ads, an advertising identifier and related ad-interaction data."
        ),
        Section(
            title: "Why we process it (legal bases)",
            body: "To create and secure your account and provide the service (performance of a contract); to keep the app safe and prevent abuse (legitimate interests); to show advertising to non-premium users (your consent, which you can withdraw); and to meet legal obligations where they apply."
        ),
        Section(
            title: "Who we share it with",
            body: "Trusted processors that run the service on our behalf: Google Firebase (authentication and database) and, for non-premium users, Google AdMob (advertising). They process data under their own terms and only as needed to provide these functions. We do not sell your personal data."
        ),
        Section(
            title: "Passwords and phone numbers",
            body: "We never store your password — Google's Firebase Authentication holds it as a secure hash. Your phone number is stored only as a salted hash plus its last 4 digits, never in plain text."
        ),
        Section(
            title: "International transfers",
            body: "Our processors may handle data on servers outside your country. Where that happens, transfers are covered by appropriate safeguards such as the European Commission's Standard Contractual Clauses."
        ),
        Section(
            title: "How long we keep it",
            body: "We keep your data for as long as your account exists. You can delete your account at any time from the Profile screen, which removes your profile data. Some records may be retained where required by law."
        ),
        Section(
            title: "Your rights",
            body: "Under the GDPR you can access, correct, delete, restrict, or object to the processing of your data, and request a portable copy. Where processing is based on consent, you can withdraw it at any time without affecting prior processing. You also have the right to lodge a complaint with your local data protection authority."
        ),
        Section(
            title: "Advertising & tracking",
            body: "If you are on the free plan, we show ads via Google AdMob. iOS will separately ask your permission before any cross-app tracking; you can decline and still use the app, and you can upgrade to remove ads entirely."
        )
    ]
}

#Preview {
    ConsentView()
        .environmentObject(AuthenticationManager.shared)
}
