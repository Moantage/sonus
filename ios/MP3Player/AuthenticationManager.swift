import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

/// Central authentication coordinator.
///
/// Security notes (see SECURITY_REVIEW.md):
/// - Firebase Auth is the single source of truth for session state.
///   Sessions are restored via the auth-state listener, never from
///   locally cached values.
/// - ID tokens are short-lived and are NOT persisted. When a token is
///   needed, fetch a fresh one with `currentFirebaseUser?.getIDToken()`.
/// - The Sign in with Apple nonce is generated with
///   `SecRandomCopyBytes` (CSPRNG), not `Int.random`.
@MainActor
final class AuthenticationManager: NSObject, ObservableObject {

    @Published var authState: AuthenticationState = .authenticating
    @Published var currentUser: User?

    static let shared = AuthenticationManager()

    private let userRepository = UserRepository()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    /// Names captured during email sign-up or Apple's first authorization,
    /// consumed when the profile document is created.
    private var pendingFirstName: String?
    private var pendingLastName: String?

    /// Providers linked to the signed-in account ("password", "google.com",
    /// "apple.com", "phone").
    var linkedProviders: [String] {
        Auth.auth().currentUser?.providerData.map { $0.providerID } ?? []
    }

    var hasPasswordProvider: Bool { linkedProviders.contains("password") }
    var linkedPhoneNumber: String? { Auth.auth().currentUser?.phoneNumber }

    override init() {
        super.init()
        listenToAuthState()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Session (Firebase is the source of truth)

    private func listenToAuthState() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            Task { @MainActor in
                if let firebaseUser {
                    await self.loadProfile(for: firebaseUser)
                } else {
                    self.currentUser = nil
                    self.authState = .unauthenticated
                }
            }
        }
    }

    private func loadProfile(for firebaseUser: FirebaseAuth.User) async {
        do {
            let user = try await userRepository.fetchOrCreateProfile(
                for: firebaseUser,
                firstName: pendingFirstName,
                lastName: pendingLastName
            )
            pendingFirstName = nil
            pendingLastName = nil
            currentUser = user
            authState = .authenticated(user: user)
        } catch {
            // Firestore unreachable — degrade gracefully with Auth data only.
            let fallback = User(
                id: firebaseUser.uid,
                email: firebaseUser.email ?? "",
                firstName: pendingFirstName ?? firebaseUser.displayName ?? "",
                lastName: pendingLastName ?? "",
                profilePhotoURL: firebaseUser.photoURL?.absoluteString,
                phoneLast4: firebaseUser.phoneNumber.map { String($0.suffix(4)) },
                isPremium: false,
                createdAt: firebaseUser.metadata.creationDate ?? Date(),
                updatedAt: Date()
            )
            currentUser = fallback
            authState = .authenticated(user: fallback)
        }
    }

    func refreshProfile() async {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        await loadProfile(for: firebaseUser)
    }

    /// Stable per-user token that links App Store purchases to this account for
    /// server-side verification (passed as StoreKit's `appAccountToken`).
    func appAccountToken() async -> UUID? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return try? await userRepository.getOrCreateAppAccountToken(uid: uid)
    }

    /// Updates the selected profile banner (Firestore + local state).
    func updateProfileBanner(_ bannerID: String) async {
        guard let user = currentUser else { return }
        do {
            try await userRepository.updateProfileBanner(uid: user.id, bannerID: bannerID)
            var updated = user
            updated.profileBanner = bannerID
            currentUser = updated
            authState = .authenticated(user: updated)
        } catch {
            // Non-fatal; leave the previous banner in place.
        }
    }

    // MARK: - GDPR consent

    /// True when a signed-in user hasn't accepted the current agreement version.
    var needsConsent: Bool {
        guard let user = currentUser else { return false }
        return user.consentVersion != ConsentConfig.currentVersion
    }

    /// Records the user's acceptance of the current agreement in Firestore
    /// (with a server timestamp) and updates local state.
    @discardableResult
    func recordConsent() async -> AuthenticationError? {
        guard let user = currentUser else { return .userNotFound }
        do {
            try await userRepository.recordConsent(uid: user.id, version: ConsentConfig.currentVersion)
            var updated = user
            updated.consentAcceptedAt = Date()
            updated.consentVersion = ConsentConfig.currentVersion
            currentUser = updated
            authState = .authenticated(user: updated)
            return nil
        } catch {
            return .networkError
        }
    }

    // MARK: - Sign in with Apple

    func prepareAppleSignInRequest() -> String {
        authState = .authenticating
        let nonce = Self.secureRandomNonce()
        currentNonce = nonce
        return Self.sha256(nonce)
    }

    func cancelAppleSignIn() {
        if case .authenticating = authState {
            authState = .unauthenticated
        }
    }

    func authenticateWithApple(authorization: ASAuthorization) async {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8),
              let nonce = currentNonce else {
            authState = .error(.signInFailed)
            return
        }
        currentNonce = nil

        // Apple only provides the name on the FIRST authorization.
        pendingFirstName = appleIDCredential.fullName?.givenName
        pendingLastName = appleIDCredential.fullName?.familyName

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        do {
            _ = try await Auth.auth().signIn(with: credential)
            // Auth-state listener completes the flow.
        } catch {
            authState = .error(Self.mapError(error))
        }
    }

    // MARK: - Sign in with Google

    func signInWithGoogle() async {
        authState = .authenticating

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            authState = .error(.unknown)
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let rootViewController = Self.rootViewController() else {
            authState = .error(.unknown)
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                authState = .error(.signInFailed)
                return
            }

            pendingFirstName = result.user.profile?.givenName
            pendingLastName = result.user.profile?.familyName

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            _ = try await Auth.auth().signIn(with: credential)
        } catch let error as GIDSignInError where error.code == .canceled {
            authState = .unauthenticated
        } catch {
            authState = .error(Self.mapError(error))
        }
    }

    // MARK: - Email & password

    /// Firebase Auth hashes the password server-side (scrypt).
    /// The password never touches Firestore or local storage.
    @discardableResult
    func signUp(email: String, password: String, firstName: String, lastName: String) async -> AuthenticationError? {
        guard password.count >= 8 else { return .weakPassword }
        pendingFirstName = firstName
        pendingLastName = lastName
        do {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
            return nil
        } catch {
            pendingFirstName = nil
            pendingLastName = nil
            return Self.mapError(error)
        }
    }

    @discardableResult
    func signIn(email: String, password: String) async -> AuthenticationError? {
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            return nil
        } catch {
            return Self.mapError(error)
        }
    }

    /// "Forgot password" — sends a secure reset link to the user's email.
    @discardableResult
    func sendPasswordReset(email: String) async -> AuthenticationError? {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            return nil
        } catch {
            return Self.mapError(error)
        }
    }

    /// Change password from within the app. Requires the current password
    /// (re-authentication) so a stolen unlocked phone can't silently
    /// take over the account.
    @discardableResult
    func changePassword(current: String, new: String) async -> AuthenticationError? {
        guard new.count >= 8 else { return .weakPassword }
        guard let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else { return .userNotFound }
        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: current)
            _ = try await firebaseUser.reauthenticate(with: credential)
            try await firebaseUser.updatePassword(to: new)
            return nil
        } catch {
            return Self.mapError(error)
        }
    }

    /// Adds a password to an account created via phone/Google/Apple,
    /// e.g. after an OTP recovery sign-in.
    @discardableResult
    func setPassword(new: String) async -> AuthenticationError? {
        guard new.count >= 8 else { return .weakPassword }
        guard let firebaseUser = Auth.auth().currentUser else { return .userNotFound }
        do {
            try await firebaseUser.updatePassword(to: new)
            return nil
        } catch {
            return Self.mapError(error)
        }
    }

    // MARK: - Phone (SMS OTP)

    /// Step 1 — send a 6-digit code. Returns a verification ID on success.
    func sendPhoneOTP(to phoneE164: String) async -> Result<String, AuthenticationError> {
        do {
            let verificationID = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(phoneE164, uiDelegate: nil)
            return .success(verificationID)
        } catch {
            return .failure(Self.mapError(error))
        }
    }

    /// Step 2 — sign in with the received code. Also serves as the
    /// account-recovery path when a password is forgotten.
    @discardableResult
    func signInWithOTP(verificationID: String, code: String) async -> AuthenticationError? {
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: code
        )
        do {
            _ = try await Auth.auth().signIn(with: credential)
            return nil
        } catch {
            return Self.mapError(error)
        }
    }

    /// Link (or replace) the phone number on the signed-in account and
    /// mirror the hashed value to Firestore.
    @discardableResult
    func linkPhone(verificationID: String, code: String, phoneE164: String) async -> AuthenticationError? {
        guard let firebaseUser = Auth.auth().currentUser else { return .userNotFound }
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: code
        )
        do {
            try await firebaseUser.updatePhoneNumber(credential)
            try await userRepository.updatePhone(uid: firebaseUser.uid, phoneE164: phoneE164)
            await refreshProfile()
            return nil
        } catch {
            return Self.mapError(error)
        }
    }

    // MARK: - Profile

    func updateUserProfile(firstName: String, lastName: String) async {
        guard let user = currentUser else {
            authState = .error(.userNotFound)
            return
        }
        do {
            try await userRepository.updateNames(uid: user.id, firstName: firstName, lastName: lastName)
            var updated = user
            updated.firstName = firstName
            updated.lastName = lastName
            updated.updatedAt = Date()
            currentUser = updated
            authState = .authenticated(user: updated)
        } catch {
            authState = .error(.networkError)
        }
    }

    // MARK: - Sign out / delete

    func signOut() {
        do {
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
            // Auth-state listener resets published state.
        } catch {
            authState = .error(.signOutFailed)
        }
    }

    /// App Store requirement: users must be able to delete their account.
    @discardableResult
    func deleteAccount() async -> AuthenticationError? {
        guard let firebaseUser = Auth.auth().currentUser else { return .userNotFound }
        do {
            try? await userRepository.deleteProfile(uid: firebaseUser.uid)
            try await firebaseUser.delete()
            return nil
        } catch {
            return Self.mapError(error) // .requiresRecentLogin → re-auth, retry
        }
    }

    // MARK: - Helpers

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    /// Cryptographically secure nonce (Apple's documented approach).
    private static func secureRandomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "Unable to generate secure nonce")

            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func mapError(_ error: Error) -> AuthenticationError {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return nsError.domain == NSURLErrorDomain ? .networkError : .signInFailed
        }
        switch code {
        case .invalidEmail: return .invalidEmail
        case .emailAlreadyInUse, .credentialAlreadyInUse: return .emailAlreadyInUse
        case .weakPassword: return .weakPassword
        case .wrongPassword, .invalidCredential: return .wrongPassword
        case .userNotFound: return .userNotFound
        case .userDisabled: return .accountDisabled
        case .invalidPhoneNumber, .missingPhoneNumber: return .invalidPhoneNumber
        case .invalidVerificationCode: return .invalidOTP
        case .sessionExpired: return .otpExpired
        case .tooManyRequests: return .tooManyRequests
        case .requiresRecentLogin: return .requiresRecentLogin
        case .networkError: return .networkError
        default: return .signInFailed
        }
    }
}
