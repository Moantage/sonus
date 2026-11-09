import SwiftUI
import UIKit

/// What Sonus is running on, so it can adapt to iOS 15, small screens and older hardware such
/// as the iPod touch (7th generation): a 4-inch, 320 × 568 pt screen and an A10 chip, which
/// stops at iOS 15.
///
/// DEBUG builds accept launch arguments that force each adaptation, so the iOS 15 code paths and
/// the 4-inch layout can be checked on a newer Simulator:
/// - `-SonusLegacyUI` takes the iOS 15 code paths (no iOS 16/17-only APIs).
/// - `-SonusCompactLayout` uses the 4-inch layout.
/// - `-SonusSimulateIPod` does both, keeps effects light, and draws the app in a 320 × 568 pt
///   frame at the top left of the window, like an iPod touch screen.
/// Release builds ignore them.
enum DeviceProfile {
    /// The hardware model, such as `iPod9,1` for the iPod touch (7th generation).
    static let modelIdentifier: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        var machine = info.machine
        let capacity = MemoryLayout.size(ofValue: machine)
        return withUnsafePointer(to: &machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }()

    static let isIPodTouch = modelIdentifier.hasPrefix("iPod") || UIDevice.current.model == "iPod touch"

    /// True on iOS 15, where the app uses its iOS 15 code paths (NavigationView, UIKit sheet
    /// detents, no symbol effects).
    static let usesLegacyUI: Bool = {
        if #available(iOS 16.0, *) {
            return LaunchFlags.legacyUI
        }
        return true
    }()

    /// A 4-inch screen, 320 pt wide: the iPod touch (7th generation), the first iPhone SE, and
    /// larger iPhones set to Display Zoom.
    static let hasCompactScreen: Bool = {
        if LaunchFlags.compactLayout { return true }
        let bounds = UIScreen.main.bounds
        return min(bounds.width, bounds.height) <= 320
    }()

    /// Every device that stops at iOS 15 has an A9 or A10 chip, as does the iPod touch, so the
    /// heaviest effects (the drifting blurred artwork behind Now Playing) stay still there.
    static let prefersLightEffects: Bool = usesLegacyUI || isIPodTouch || LaunchFlags.simulateIPod

    /// A one-line summary for logs and bug reports.
    static var summary: String {
        let bounds = UIScreen.main.bounds
        return "\(modelIdentifier), iOS \(UIDevice.current.systemVersion), "
            + "\(Int(bounds.width))×\(Int(bounds.height)) pt"
            + (hasCompactScreen ? ", compact layout" : "")
            + (usesLegacyUI ? ", iOS 15 paths" : "")
            + (prefersLightEffects ? ", light effects" : "")
    }
}

/// DEBUG-only switches for checking the iPod adaptations on a newer Simulator.
enum LaunchFlags {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    static let simulateIPod = arguments.contains("-SonusSimulateIPod")
    static let legacyUI = simulateIPod || arguments.contains("-SonusLegacyUI")
    static let compactLayout = simulateIPod || arguments.contains("-SonusCompactLayout")
    #else
    static let simulateIPod = false
    static let legacyUI = false
    static let compactLayout = false
    #endif

    /// The iPod touch screen in points.
    static let simulatedScreen = CGSize(width: 320, height: 568)
}

// MARK: - Screen metrics

/// Sizes that change on a 4-inch screen. Everything else in the layout is flexible already.
///
/// On a 320 pt screen Now Playing has about 270 pt of width and 550 pt of height for the artwork,
/// the title, the scrubber and the controls, and the regular transport row (284 pt) doesn't fit.
enum ScreenMetrics {
    static let isCompact = DeviceProfile.hasCompactScreen

    // MARK: Pages

    /// Side margin of the tab pages.
    static var pageMargin: CGFloat { isCompact ? 12 : 16 }
    /// Space between sections on Home and Profile.
    static var sectionSpacing: CGFloat { isCompact ? 22 : 28 }

    // MARK: Home

    /// Song and playlist cards in the Home carousels.
    static var carouselCard: CGFloat { isCompact ? 124 : 150 }
    /// The artwork on Home's hero card.
    static var heroArtwork: CGFloat { isCompact ? 80 : 116 }
    /// The artwork on Home's two-column shortcuts.
    static var shortcutArtwork: CGFloat { isCompact ? 48 : 56 }

    // MARK: Lists and collections

    /// The artwork at the top of a playlist or collection page.
    static var collectionArtwork: CGFloat { isCompact ? 176 : 232 }
    /// Collection and playlist rows in Your Library.
    static var libraryRowArtwork: CGFloat { isCompact ? 54 : 64 }
    /// Song rows.
    static var songRowArtwork: CGFloat { isCompact ? 44 : 48 }
    /// Search's browse tiles.
    static var browseTileHeight: CGFloat { isCompact ? 84 : 96 }

    // MARK: Player

    static var miniPlayerHeight: CGFloat { isCompact ? 58 : 64 }
    static var miniPlayerArtwork: CGFloat { isCompact ? 42 : 46 }
    static var tabBarHeight: CGFloat { isCompact ? 46 : 50 }
    static var tabIconSize: CGFloat { isCompact ? 20 : 22 }

    /// Now Playing's side margin.
    static var playerMargin: CGFloat { isCompact ? 20 : 24 }
    /// The big play/pause button.
    static var playButton: CGFloat { isCompact ? 64 : 76 }
    static var playIcon: CGFloat { isCompact ? 27 : 32 }
    /// Previous and next.
    static var skipButton: CGFloat { isCompact ? 48 : 60 }
    static var skipIcon: CGFloat { isCompact ? 26 : 32 }
    /// Vertical breathing room between Now Playing's rows.
    static var playerRowSpacing: CGFloat { isCompact ? 10 : 18 }

    // MARK: Controls

    /// Height of the full-width pill buttons.
    static var pillHeight: CGFloat { isCompact ? 46 : 52 }
    /// The logo tile on Login and Onboarding.
    static var brandTile: CGFloat { isCompact ? 60 : 76 }
}
