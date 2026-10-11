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
        FirebaseApp.configure()
        AdsManager.shared.start()
        // Link StoreKit purchases to the signed-in user for server verification.
        Task { @MainActor in
            StoreManager.shared.appAccountTokenProvider = {
                await AuthenticationManager.shared.appAccountToken()
            }
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AdsManager.shared.requestTrackingAuthorizationIfNeeded()
        // Re-check StoreKit entitlements every time the app comes to the
        // foreground so a lapsed subscription brings ads back promptly (an
        // expiration that happens while backgrounded won't always push an update).
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
    @State private var selectedTab = 0   // 0 = Music, 1 = Profile

    /// AD GATING — verified purchase only. Ads are removed solely for users with
    /// a real, Apple-verified StoreKit entitlement (active subscription or
    /// lifetime). A manually-set Firestore `isPremium` flag does NOT remove ads.
    private var adsSuppressed: Bool {
        AdGate.adsSuppressed(store: store)
    }

    /// FEATURE ACCESS — more lenient. StoreKit entitlement OR the Firestore flag
    /// (which lets you grant premium features via promo/support/console). This is
    /// intentionally separate from ad gating and must never feed `bannerAds`.
    private var premiumFeaturesUnlocked: Bool {
        store.isPremium || authManager.currentUser?.isPremium == true
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
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
                            TabView(selection: $selectedTab) {
                                ContentView()
                                    .bannerAds(adsSuppressed: adsSuppressed)
                                    .tabItem { Label("Listen", systemImage: "music.note") }
                                    .environmentObject(libraryStore)
                                    .environmentObject(audioPlayerManager)
                                    .tag(0)

                                ProfileView()
                                    .bannerAds(adsSuppressed: adsSuppressed)
                                    .tabItem { Label("You", systemImage: "person.circle") }
                                    .environmentObject(audioPlayerManager)
                                    .environmentObject(libraryStore)
                                    .tag(1)
                                    .simultaneousGesture(
                                        // Left-edge swipe to the right → back to the music list.
                                        // Gated to edge-start + mostly-horizontal so it never
                                        // interferes with vertical scrolling in Profile.
                                        DragGesture(minimumDistance: 20, coordinateSpace: .global)
                                            .onEnded { value in
                                                if value.startLocation.x < 24,
                                                   value.translation.width > 70,
                                                   abs(value.translation.height) < 60 {
                                                    withAnimation { selectedTab = 0 }
                                                }
                                            }
                                    )
                            }
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
            .tint(Theme.accent)            // amber accent for system controls & tab bar
            .preferredColorScheme(.light)
            .onOpenURL { url in
                _ = GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
