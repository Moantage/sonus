import SwiftUI
import UIKit
import GoogleMobileAds
import AppTrackingTransparency

/// Google AdMob banner integration for non-premium users.
///
/// Real AdMob identifiers are never committed. They come from build settings:
///   1. `ADMOB_APP_ID`         → Info.plist `GADApplicationIdentifier`
///   2. `ADMOB_BANNER_UNIT_ID` → Info.plist `SonusAdMobBannerUnitID` → `realBannerUnitID`
/// `Config.xcconfig` (tracked) defaults both to Google's public TEST IDs; the official
/// build overrides them in `Secrets.xcconfig` (gitignored).
///
/// Never ship the test IDs, and never tap your own live ads — either will get
/// your AdMob account suspended.
enum AdConfig {
    /// Google's public test banner unit ID (iOS). Always safe.
    static let testBannerUnitID = "ca-app-pub-3940256099942544/2435281174"

    /// Your real banner ad unit ID, injected via Info.plist from `ADMOB_BANNER_UNIT_ID`.
    /// Falls back to the test unit if the build setting is missing or malformed.
    static var realBannerUnitID: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SonusAdMobBannerUnitID") as? String,
              value.hasPrefix("ca-app-pub-") else {
            return testBannerUnitID
        }
        return value
    }

    /// Test ads in DEBUG, your real unit in release builds.
    static var bannerUnitID: String {
        #if DEBUG
        return testBannerUnitID
        #else
        return realBannerUnitID
        #endif
    }
}

/// Starts the Mobile Ads SDK and handles the App Tracking Transparency prompt.
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

    /// Ask for tracking permission so ads can be personalized (higher revenue).
    /// Ads still serve non-personalized if the user declines — nothing breaks.
    /// Call once the UI is on screen.
    func requestTrackingAuthorizationIfNeeded() {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        // Delay slightly so the system prompt doesn't collide with launch UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}

/// An anchored adaptive banner wrapped for SwiftUI.
struct AnchoredAdaptiveBanner: UIViewRepresentable {
    let adUnitID: String
    let adSize: AdSize

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = Self.rootViewController()
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("AdMob banner failed to load: \(error.localizedDescription)")
        }
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

/// SINGLE SOURCE OF TRUTH for whether ads should be hidden.
///
/// Ads (banners, and any interstitial/other formats added later) are suppressed
/// **only** by a VERIFIED premium entitlement:
///   • `StoreManager.isPremium` — an active StoreKit entitlement (auto-renewable
///     subscription that hasn't expired, or a lifetime non-consumable). Apple
///     verifies this cryptographically on-device via `Transaction.currentEntitlements`,
///     and it is automatically dropped when a subscription lapses → ads return.
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

/// A single banner strip sized to the current device width.
private struct BannerStrip: View {
    var body: some View {
        let width = UIScreen.main.bounds.width
        let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        AnchoredAdaptiveBanner(adUnitID: AdConfig.bannerUnitID, adSize: adSize)
            .frame(width: adSize.size.width, height: adSize.size.height)
            .frame(maxWidth: .infinity)
            .background(Theme.backgroundBottom)
    }
}

extension View {
    /// Adds top + bottom anchored banners. Pass `adsSuppressed` from
    /// `AdGate.adsSuppressed(store:)` — banners show whenever it is false.
    /// When true (verified purchaser), no banners are attached at all.
    @ViewBuilder
    func bannerAds(adsSuppressed: Bool) -> some View {
        if adsSuppressed {
            self
        } else {
            self
                .safeAreaInset(edge: .top, spacing: 0) { BannerStrip() }
                .safeAreaInset(edge: .bottom, spacing: 0) { BannerStrip() }
        }
    }
}
