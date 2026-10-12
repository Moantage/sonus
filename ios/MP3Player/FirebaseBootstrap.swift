import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Starts Firebase: the real project from `GoogleService-Info.plist`, or, in DEBUG builds
/// launched with `-SonusFirebaseEmulator`, the Firebase Local Emulator Suite.
///
/// Emulator mode uses the offline `demo-sonus` project, so it needs no `GoogleService-Info.plist`
/// and never reaches a real Firebase project. Start the emulators with `npm run emulators` (see
/// CONTRIBUTING.md). They're expected on 127.0.0.1; set `SONUS_FIREBASE_EMULATOR_HOST` to reach
/// them on another machine, e.g. from a physical device.
enum FirebaseBootstrap {
    static func configure() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SonusFirebaseEmulator") {
            configureEmulator()
            return
        }
        #endif
        FirebaseApp.configure()
    }

    #if DEBUG
    /// `demo-` project IDs are offline-only: the emulators never contact a real project for them.
    static let emulatorProjectID = "demo-sonus"
    static let authEmulatorPort = 9099
    static let firestoreEmulatorPort = 8080

    private static func configureEmulator() {
        let options = FirebaseOptions(
            googleAppID: "1:123456789012:ios:0123456789abcdef",
            gcmSenderID: "123456789012"
        )
        options.projectID = emulatorProjectID
        options.apiKey = "demo-sonus-emulator-key"
        options.bundleID = Bundle.main.bundleIdentifier ?? "com.novoralabs.mp3player"
        FirebaseApp.configure(options: options)

        let host = ProcessInfo.processInfo.environment["SONUS_FIREBASE_EMULATOR_HOST"] ?? "127.0.0.1"
        Auth.auth().useEmulator(withHost: host, port: authEmulatorPort)

        let firestore = Firestore.firestore()
        // Emulator data is wiped and reseeded freely, so don't keep an on-disk cache of it.
        let settings = firestore.settings
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings
        firestore.useEmulator(withHost: host, port: firestoreEmulatorPort)
    }
    #endif
}
