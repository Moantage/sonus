import Foundation
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

/// Reads and writes user profiles in Cloud Firestore.
///
/// Document layout — `users/{uid}`:
///   uid, email, firstName, lastName, profilePhotoURL,
///   hashedPhone (SHA-256, salted), phoneLast4, isPremium,
///   authProviders, createdAt, updatedAt
///
/// Notes:
/// - Passwords are NEVER stored here. Firebase Auth manages password
///   hashing (scrypt) internally on Google's servers.
/// - Phone numbers are stored only as a salted hash plus the last 4
///   digits for display. The verified number itself lives in Firebase Auth.
/// - `isPremium` is written as `false` on account creation and is
///   protected by Firestore security rules so the client cannot flip it.
///   Set it from a trusted environment (Cloud Function / server) after
///   a verified purchase.
struct UserRepository {

    private var db: Firestore { Firestore.firestore() }

    /// App-specific salt for phone hashing. Raises the cost of matching
    /// hashes against other leaked datasets. Note: because the phone number
    /// space is small, treat this as obfuscation, not encryption — real
    /// protection comes from Firestore rules restricting reads to the owner.
    private static let phoneHashSalt = "mp3player.v1.phone"

    // MARK: - Fetch

    func fetchProfile(uid: String) async throws -> User? {
        let snapshot = try await db.collection("users").document(uid).getDocument()
        guard let data = snapshot.data() else { return nil }
        return Self.user(from: data, uid: uid)
    }

    // MARK: - Create

    /// Creates the profile document on first sign-in; returns the existing
    /// profile on subsequent sign-ins.
    func fetchOrCreateProfile(
        for firebaseUser: FirebaseAuth.User,
        firstName: String?,
        lastName: String?
    ) async throws -> User {
        if let existing = try await fetchProfile(uid: firebaseUser.uid) {
            return existing
        }

        let now = Date()
        var first = firstName ?? ""
        var last = lastName ?? ""
        if first.isEmpty, let displayName = firebaseUser.displayName {
            let parts = displayName.split(separator: " ", maxSplits: 1)
            first = parts.first.map(String.init) ?? ""
            last = parts.count > 1 ? String(parts[1]) : last
        }

        var payload: [String: Any] = [
            "uid": firebaseUser.uid,
            "email": firebaseUser.email ?? "",
            "firstName": first,
            "lastName": last,
            "isPremium": false,
            "authProviders": firebaseUser.providerData.map { $0.providerID },
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ]

        if let photoURL = firebaseUser.photoURL?.absoluteString {
            payload["profilePhotoURL"] = photoURL
        }

        if let phone = firebaseUser.phoneNumber {
            payload["hashedPhone"] = Self.hashPhone(phone)
            payload["phoneLast4"] = String(phone.suffix(4))
        }

        try await db.collection("users").document(firebaseUser.uid).setData(payload)

        return User(
            id: firebaseUser.uid,
            email: firebaseUser.email ?? "",
            firstName: first,
            lastName: last,
            profilePhotoURL: firebaseUser.photoURL?.absoluteString,
            phoneLast4: firebaseUser.phoneNumber.map { String($0.suffix(4)) },
            isPremium: false,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Update

    func updateNames(uid: String, firstName: String, lastName: String) async throws {
        try await db.collection("users").document(uid).updateData([
            "firstName": firstName,
            "lastName": lastName,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    func updatePhone(uid: String, phoneE164: String) async throws {
        try await db.collection("users").document(uid).updateData([
            "hashedPhone": Self.hashPhone(phoneE164),
            "phoneLast4": String(phoneE164.suffix(4)),
            "updatedAt": Timestamp(date: Date())
        ])
    }

    /// Returns a stable per-user `appAccountToken` (a UUID) used to link App
    /// Store purchases to this user for server-side verification. Created and
    /// stored on first use, then reused. Also writes a create-only reverse-map
    /// doc (`purchaseTokens/{token}`) that the Cloud Function reads.
    func getOrCreateAppAccountToken(uid: String) async throws -> UUID {
        let ref = db.collection("users").document(uid)
        let snapshot = try await ref.getDocument()
        if let existing = snapshot.data()?["appAccountToken"] as? String,
           let uuid = UUID(uuidString: existing) {
            return uuid
        }

        let token = UUID()
        try await ref.setData(["appAccountToken": token.uuidString], merge: true)
        // Best-effort reverse map for the ASSN webhook. Create-only per rules;
        // safe to ignore failures (falls back to the users query on the server).
        try? await db.collection("purchaseTokens").document(token.uuidString).setData([
            "uid": uid,
            "createdAt": FieldValue.serverTimestamp()
        ])
        return token
    }

    func updateProfileBanner(uid: String, bannerID: String) async throws {
        try await db.collection("users").document(uid).updateData([
            "profileBanner": bannerID,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    /// Records that the user accepted the GDPR agreement, with a server-side
    /// timestamp (authoritative) and the policy version they agreed to.
    func recordConsent(uid: String, version: String) async throws {
        try await db.collection("users").document(uid).updateData([
            "consentAcceptedAt": FieldValue.serverTimestamp(),
            "consentVersion": version,
            "updatedAt": Timestamp(date: Date())
        ])
    }

    func deleteProfile(uid: String) async throws {
        try await db.collection("users").document(uid).delete()
    }

    // MARK: - Helpers

    static func hashPhone(_ phoneE164: String) -> String {
        let normalized = phoneE164.filter { $0.isNumber || $0 == "+" }
        let digest = SHA256.hash(data: Data((phoneHashSalt + normalized).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func user(from data: [String: Any], uid: String) -> User {
        User(
            id: uid,
            email: data["email"] as? String ?? "",
            firstName: data["firstName"] as? String ?? "",
            lastName: data["lastName"] as? String ?? "",
            profilePhotoURL: data["profilePhotoURL"] as? String,
            phoneLast4: data["phoneLast4"] as? String,
            isPremium: data["isPremium"] as? Bool ?? false,
            profileBanner: data["profileBanner"] as? String,
            consentAcceptedAt: (data["consentAcceptedAt"] as? Timestamp)?.dateValue(),
            consentVersion: data["consentVersion"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}
