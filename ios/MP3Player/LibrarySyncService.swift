import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Syncs the LIBRARY METADATA (songs list, playlists, order) to Firestore so a
/// user can sign in on another device and see their library. Works on the
/// Firebase **Spark (free)** plan.
///
/// It does NOT move the audio files themselves — hosting the audio bytes needs
/// Firebase Storage (Blaze plan) or your own file host. Songs synced from
/// another device show up as "in the cloud" until their file is downloaded
/// (see DownloadManager). The snapshot is stored as one JSON document at
/// `users/{uid}/library/snapshot`, well under Firestore's 1 MiB doc limit for
/// typical libraries.
@MainActor
final class LibrarySyncService: ObservableObject {

    enum Status: Equatable {
        case idle, syncing, synced, error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastSyncedAt: Date?

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var docRef: DocumentReference? {
        guard let uid else { return nil }
        return db.collection("users").document(uid).collection("library").document("snapshot")
    }

    // MARK: - Push

    /// Uploads the current library snapshot to the cloud.
    func push(_ snapshot: LibrarySnapshot) async {
        guard let docRef else { status = .error("Not signed in"); return }
        status = .syncing
        do {
            let json = try encoder.encode(snapshot)
            let payload: [String: Any] = [
                "snapshot": String(data: json, encoding: .utf8) ?? "",
                "songCount": snapshot.songs.count,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await docRef.setData(payload)
            lastSyncedAt = Date()
            status = .synced
        } catch {
            status = .error("Couldn't upload your library.")
        }
    }

    // MARK: - Pull

    /// Fetches the cloud library snapshot, if any.
    func pull() async -> LibrarySnapshot? {
        guard let docRef else { status = .error("Not signed in"); return nil }
        status = .syncing
        do {
            let snap = try await docRef.getDocument()
            guard let raw = snap.data()?["snapshot"] as? String,
                  let data = raw.data(using: .utf8) else {
                status = .synced
                return nil
            }
            let snapshot = try decoder.decode(LibrarySnapshot.self, from: data)
            lastSyncedAt = (snap.data()?["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            status = .synced
            return snapshot
        } catch {
            status = .error("Couldn't fetch your cloud library.")
            return nil
        }
    }
}
