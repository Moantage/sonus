import Foundation

// MARK: - User Models

struct User: Identifiable, Codable {
    let id: String  // Firebase UID
    var email: String
    var firstName: String
    var lastName: String
    var profilePhotoURL: String?
    /// Last 4 digits of the linked phone number, for display only.
    /// The full number is never stored in Firestore — only a salted hash.
    var phoneLast4: String?
    var isPremium: Bool
    /// Selected profile banner id (see ProfileBanner). nil = Classic (free).
    var profileBanner: String? = nil
    /// When the user accepted the GDPR terms & privacy agreement (nil = not yet).
    var consentAcceptedAt: Date? = nil
    /// Which version of the agreement they accepted, so policy changes can re-prompt.
    var consentVersion: String? = nil
    var createdAt: Date
    var updatedAt: Date

    var displayName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
}

enum AuthenticationError: LocalizedError, Equatable {
    case invalidCredentials
    case signInFailed
    case signOutFailed
    case userNotFound
    case networkError
    case invalidEmail
    case emailAlreadyInUse
    case weakPassword
    case wrongPassword
    case invalidPhoneNumber
    case invalidOTP
    case otpExpired
    case tooManyRequests
    case requiresRecentLogin
    case accountDisabled
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials provided."
        case .signInFailed:
            return "Sign in failed. Please try again."
        case .signOutFailed:
            return "Sign out failed. Please try again."
        case .userNotFound:
            return "No account found with these details."
        case .networkError:
            return "Network error. Please check your connection."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .emailAlreadyInUse:
            return "An account already exists with this email."
        case .weakPassword:
            return "Password must be at least 8 characters."
        case .wrongPassword:
            return "Incorrect email or password."
        case .invalidPhoneNumber:
            return "Please enter a valid phone number, including country code."
        case .invalidOTP:
            return "That code isn't right. Please try again."
        case .otpExpired:
            return "The code has expired. Request a new one."
        case .tooManyRequests:
            return "Too many attempts. Please wait a moment and try again."
        case .requiresRecentLogin:
            return "For security, please sign in again before making this change."
        case .accountDisabled:
            return "This account has been disabled."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

enum AuthenticationState {
    case unauthenticated
    case authenticating
    case authenticated(user: User)
    case error(AuthenticationError)
}
