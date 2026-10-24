import SwiftUI
import UIKit
import GoogleMobileAds
import AppTrackingTransparency

/// Google AdMob full-screen ads for users without a verified purchase.
///
/// The ad model:
///   • one **app open** ad when Sonus is launched (cold start), once the signed-in app is on
///     screen;
///   • one **interstitial** after every 20 minutes of listening, shown at the next song change
///     (never mid-song) while the app is in the foreground. Music pauses for the ad and resumes
///     after it.
/// The lifetime Premium purchase removes both (see `AdGate`). There are no
/// banner ads.
///
/// Real AdMob identifiers are never committed. They come from build settings:
///   `ADMOB_APP_ID`               → Info.plist `GADApplicationIdentifier`
///   `ADMOB_APP_OPEN_UNIT_ID`     → Info.plist `SonusAdMobAppOpenUnitID`
///   `ADMOB_INTERSTITIAL_UNIT_ID` → Info.plist `SonusAdMobInterstitialUnitID`
/// `Config.xcconfig` (tracked) defaults them to Google's public TEST IDs; the official build
/// overrides them in `Secrets.xcconfig` (gitignored).
///
/// Never ship the test IDs, and never tap your own live ads — either will get your AdMob
/// account suspended.
enum AdConfig {
    /// Google's public test units (iOS). Always safe.
    static let testAppOpenUnitID = "ca-app-pub-3940256099942544/5575463023"
    static let testInterstitialUnitID = "ca-app-pub-3940256099942544/4411468910"

    /// Test ads in DEBUG, the real units in release builds.
    static var appOpenUnitID: String {
        unitID(infoKey: "SonusAdMobAppOpenUnitID", test: testAppOpenUnitID)
    }

    static var interstitialUnitID: String {
        unitID(infoKey: "SonusAdMobInterstitialUnitID", test: testInterstitialUnitID)
    }

    /// Listening time between interstitials. DEBUG builds accept `-SonusAdIntervalSeconds <n>` so
    /// the interstitial can be tested without listening for 20 minutes.
    static var listeningInterval: TimeInterval {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "SonusAdIntervalSeconds") != nil {
            return max(defaults.double(forKey: "SonusAdIntervalSeconds"), 5)
        }
        #endif
        return 20 * 60
    }
    /// An app open ad that isn't ready this soon after launch is skipped, not shown late.
    static let appOpenLoadTimeout: Duration = .seconds(4)
    /// App open ads expire after four hours.
    static let appOpenAdLifetime: TimeInterval = 4 * 60 * 60

    private static func unitID(infoKey: String, test: String) -> String {
        #if DEBUG
        return test
        #else
        // Falls back to the test unit if the build setting is missing or malformed.
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
              value.hasPrefix("ca-app-pub-") else {
            return test
        }
        return value
        #endif
    }
}

/// Starts the Mobile Ads SDK. The App Tracking Transparency prompt is asked by
/// `FullScreenAdController.handleLaunch()` once the signed-in app is on screen.
final class AdsManager {
    static let shared = AdsManager()
    private var started = false
    private init() {}

    /// Initialize the SDK once. Safe to call on every launch.
    func start() {
        guard !started else { return }
        started = true
        MobileAds.shared.start(completionHandler: nil)
    }

}

/// SINGLE SOURCE OF TRUTH for whether ads should be hidden.
///
/// Ads are suppressed **only** by a VERIFIED premium entitlement:
///   • `StoreManager.isPremium` — the lifetime non-consumable StoreKit entitlement.
///     Apple verifies it cryptographically on-device via `Transaction.currentEntitlements`,
///     and it is dropped if the purchase is refunded → ads return.
///
/// A manually-set Firestore `isPremium` flag is deliberately NOT consulted here:
/// it is not a verified purchase, so it must NOT remove ads. If/when you add
/// server-side receipt verification (a Blaze Cloud Function that validates the
/// App Store receipt), OR-in that trusted, server-only signal below — and only
/// that. Never OR-in the raw, client-writable `isPremium` flag.
///
/// EVERY place that shows an ad must gate on `AdGate.adsSuppressed(store:)`.
@MainActor
enum AdGate {
    static func adsSuppressed(store: StoreManager) -> Bool {
        store.isPremium
        // || <server-verified purchase flag here, once you add receipt verification>
    }
}

/// Loads and shows the full-screen ads, and counts listening time between interstitials.
@MainActor
final class FullScreenAdController: NSObject, ObservableObject, FullScreenContentDelegate {
    private var appOpenAd: AppOpenAd?
    private var appOpenAdLoadedAt: Date?
    private var interstitial: InterstitialAd?
    private var isLoadingAppOpen = false
    private var isLoadingInterstitial = false

    private var didHandleLaunch = false
    private var isShowingAd = false
    private var resumeAfterAd = false

    /// Listening time since the last ad (or since launch).
    private(set) var listenedSeconds: TimeInterval = 0
    private var lastTick: Date?
    private var ticker: Timer?

    private weak var player: AudioPlayerManager?
    private weak var store: StoreManager?

    func attach(player: AudioPlayerManager, store: StoreManager) {
        self.player = player
        self.store = store
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private var adsAllowed: Bool {
        guard let store else { return false }
        return !AdGate.adsSuppressed(store: store)
    }

    // MARK: App open (once per cold launch)

    /// Call when the signed-in app first appears. Shows an app open ad if one loads quickly.
    /// On a user's first launch this asks for tracking permission instead and skips the ad, so
    /// the system prompt and the ad never collide.
    func handleLaunch() async {
        guard !didHandleLaunch else { return }
        didHandleLaunch = true
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            // iOS only shows the prompt once the app is fully active.
            for _ in 0..<50 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(500))
            _ = await ATTrackingManager.requestTrackingAuthorization()
            loadInterstitialIfNeeded()
            return
        }
        // Make sure a paying user's entitlement is loaded before deciding to show an ad.
        await store?.refreshEntitlements()
        guard adsAllowed else { return }

        let deadline = ContinuousClock.now + AdConfig.appOpenLoadTimeout
        loadAppOpenIfNeeded()
        while appOpenAd == nil, isLoadingAppOpen, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let readyAd = appOpenAd, adsAllowed, UIApplication.shared.applicationState == .active {
            present(readyAd)
        }
        loadInterstitialIfNeeded()
    }

    private func loadAppOpenIfNeeded() {
        if let loadedAt = appOpenAdLoadedAt, Date().timeIntervalSince(loadedAt) > AdConfig.appOpenAdLifetime {
            appOpenAd = nil
        }
        guard appOpenAd == nil, !isLoadingAppOpen else { return }
        isLoadingAppOpen = true
        AppOpenAd.load(with: AdConfig.appOpenUnitID, request: Request()) { [weak self] loadedAd, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingAppOpen = false
                if let error { print("AdMob app open ad failed to load: \(error.localizedDescription)") }
                self.appOpenAd = loadedAd
                self.appOpenAdLoadedAt = loadedAd == nil ? nil : Date()
                loadedAd?.fullScreenContentDelegate = self
            }
        }
    }

    // MARK: Interstitial (every 20 minutes of listening)

    private func tick() {
        let now = Date()
        defer { lastTick = now }
        guard let player, player.isPlaying, !isShowingAd, let lastTick else { return }
        // Cap each step so a suspended timer can't jump the counter.
        listenedSeconds += min(now.timeIntervalSince(lastTick), 2)
        if listenedSeconds >= AdConfig.listeningInterval - 60 { loadInterstitialIfNeeded() }
    }

    /// Call when the current song changes. Shows the interstitial at this song boundary once
    /// the listening interval has passed and the app is in the foreground.
    func songDidChange() {
        guard adsAllowed,
              listenedSeconds >= AdConfig.listeningInterval,
              UIApplication.shared.applicationState == .active,
              let readyAd = interstitial else {
            if listenedSeconds >= AdConfig.listeningInterval { loadInterstitialIfNeeded() }
            return
        }
        present(readyAd)
    }

    private func loadInterstitialIfNeeded() {
        guard adsAllowed, interstitial == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true
        InterstitialAd.load(with: AdConfig.interstitialUnitID, request: Request()) { [weak self] loadedAd, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingInterstitial = false
                if let error { print("AdMob interstitial failed to load: \(error.localizedDescription)") }
                self.interstitial = loadedAd
                loadedAd?.fullScreenContentDelegate = self
            }
        }
    }

    // MARK: Presenting

    private func present(_ fullScreenAd: FullScreenPresentingAd) {
        guard !isShowingAd, let root = Self.topViewController() else { return }
        isShowingAd = true
        resumeAfterAd = player?.isPlaying == true
        if resumeAfterAd { player?.pause() }
        if let appOpen = fullScreenAd as? AppOpenAd {
            appOpen.present(from: root)
        } else if let interstitialAd = fullScreenAd as? InterstitialAd {
            interstitialAd.present(from: root)
        }
    }

    func adDidDismissFullScreenContent(_ fullScreenAd: FullScreenPresentingAd) {
        finish(fullScreenAd)
    }

    func ad(_ fullScreenAd: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("AdMob ad failed to present: \(error.localizedDescription)")
        finish(fullScreenAd)
    }

    private func finish(_ fullScreenAd: FullScreenPresentingAd) {
        isShowingAd = false
        if fullScreenAd is AppOpenAd {
            appOpenAd = nil
            appOpenAdLoadedAt = nil
        } else {
            interstitial = nil
        }
        // Any full-screen ad restarts the listening interval.
        listenedSeconds = 0
        if resumeAfterAd { player?.resume() }
        resumeAfterAd = false
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
