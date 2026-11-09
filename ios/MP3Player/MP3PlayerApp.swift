import SwiftUI
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

/// Handles Firebase configuration plus the callbacks that phone
/// authentication (silent APNs push / reCAPTCHA redirect) and Google
/// Sign-In require.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configure()
        AdsManager.shared.start()
        LegacyAppearance.apply()
        #if DEBUG
        print("[Sonus] Device: \(DeviceProfile.summary)")
        #endif
        // Link StoreKit purchases to the signed-in user for server verification.
        Task { @MainActor in
            StoreManager.shared.appAccountTokenProvider = {
                await AuthenticationManager.shared.appAccountToken()
            }
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Re-check StoreKit entitlements every time the app comes to the
        // foreground so a refunded purchase brings ads back promptly (a
        // revocation that happens while backgrounded won't always push an update).
        Task { @MainActor in await StoreManager.shared.refreshEntitlements() }
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if Auth.auth().canHandle(url) { return true }
        return GIDSignIn.sharedInstance.handle(url)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.noData)
    }
}

@main
struct MP3PlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var audioPlayerManager = AudioPlayerManager()
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var store = StoreManager.shared
    @StateObject private var librarySync = LibrarySyncService()
    @StateObject private var downloadManager = DownloadManager()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// FEATURE ACCESS — more lenient. StoreKit entitlement OR the Firestore flag
    /// (which lets you grant premium features via promo/support/console). This is
    /// intentionally separate from ad gating and must never feed `AdGate`.
    private var premiumFeaturesUnlocked: Bool {
        store.isPremium || authManager.currentUser?.isPremium == true
    }

    #if DEBUG
    /// UI review only: launching with `-SonusUIReview` opens the signed-in shell without a
    /// Firebase sign-in, so screens can be checked in the Simulator with local test songs.
    /// Compiled out of release builds.
    private let isUIReview = ProcessInfo.processInfo.arguments.contains("-SonusUIReview")
    #else
    private let isUIReview = false
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                if isUIReview {
                    ContentView()
                        .environmentObject(libraryStore)
                        .environmentObject(audioPlayerManager)
                } else if !hasCompletedOnboarding {
                    OnboardingView()
                } else {
                    switch authManager.authState {
                    case .unauthenticated, .error:
                        LoginView()

                    case .authenticating:
                        ZStack {
                            Theme.background
                            ProgressView().tint(Theme.accent)
                        }

                    case .authenticated:
                        if authManager.needsConsent {
                            ConsentView()
                        } else {
                            ContentView()
                                .environmentObject(libraryStore)
                                .environmentObject(audioPlayerManager)
                                .task {
                                    // Cloud library sync is a premium FEATURE (not ad
                                    // gating), so the lenient check is fine here.
                                    guard premiumFeaturesUnlocked else { return }
                                    if let remote = await librarySync.pull() {
                                        libraryStore.mergeRemoteSnapshot(remote)
                                    }
                                }
                        }
                    }
                }
            }
            .environmentObject(authManager)
            .environmentObject(store)
            .environmentObject(librarySync)
            .environmentObject(downloadManager)
            .tint(Theme.accent)            // amber accent for system controls
            .accentColor(Theme.accent)     // iOS 15 navigation bars and alerts follow this one
            .preferredColorScheme(.dark)   // Ember is dark only
            .simulatedIPodScreen()
            .onOpenURL { url in
                _ = GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}

private extension View {
    /// DEBUG `-SonusSimulateIPod`: draws the app in a 320 × 568 pt frame at the top left, the size
    /// of the iPod touch (7th generation) screen. Run it on an iPhone SE (3rd generation), whose
    /// status bar and missing home indicator match the iPod's. Sheets still use the full window.
    @ViewBuilder
    func simulatedIPodScreen() -> some View {
        if LaunchFlags.simulateIPod {
            // The status bar (20 pt) stays above the frame, as on the iPod.
            frame(width: LaunchFlags.simulatedScreen.width, height: LaunchFlags.simulatedScreen.height - 20)
                // Clip to the screen, but let backgrounds reach up under the status bar.
                .mask(Rectangle().padding(.top, -20))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(white: 0.25).ignoresSafeArea())
        } else {
            self
        }
    }
}
