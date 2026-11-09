import SwiftUI
import UIKit

// iOS 15 support. Sonus runs on iOS 15 for the iPod touch (7th generation), which can't update
// past it. The helpers below use the iOS 16/17 API when it's there and an iOS 15 equivalent
// otherwise, so views call one modifier and stay readable. `DeviceProfile.usesLegacyUI` also
// lets DEBUG builds force the iOS 15 paths on a newer Simulator.
//
// When the deployment target moves past iOS 16 or 17, the matching fallbacks can go.

// MARK: - Haptics

/// Haptic feedback with an iOS 15 fallback. iOS 17 uses `sensoryFeedback`; older systems use
/// UIKit's feedback generators. Devices without a Taptic Engine (the iPod touch) stay silent.
enum Haptic: Equatable {
    case selection
    case success
    case light
    case medium
    /// A soft impact at the given intensity (0–1).
    case soft(Double)

    @available(iOS 17.0, *)
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .selection: return .selection
        case .success: return .success
        case .light: return .impact(weight: .light)
        case .medium: return .impact(weight: .medium)
        case .soft(let intensity): return .impact(flexibility: .soft, intensity: intensity)
        }
    }

    @MainActor
    func play() {
        switch self {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .soft(let intensity): UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: CGFloat(intensity))
        }
    }
}

private struct HapticModifier<Trigger: Equatable>: ViewModifier {
    let haptic: Haptic
    let trigger: Trigger
    let condition: (Trigger) -> Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), !DeviceProfile.usesLegacyUI {
            content.sensoryFeedback(haptic.sensoryFeedback, trigger: trigger) { _, newValue in condition(newValue) }
        } else {
            content.onChange(of: trigger) { newValue in
                if condition(newValue) { haptic.play() }
            }
        }
    }
}

// MARK: - Symbol effects and content transitions

private struct SymbolBounceModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let down: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), !DeviceProfile.usesLegacyUI {
            if down {
                content.symbolEffect(.bounce.down, value: value)
            } else {
                content.symbolEffect(.bounce, value: value)
            }
        } else {
            content
        }
    }
}

private struct ContentTransitionModifier: ViewModifier {
    enum Kind {
        case symbolReplace
        case opacity
    }

    let kind: Kind

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), !DeviceProfile.usesLegacyUI {
            switch kind {
            case .symbolReplace: content.contentTransition(.symbolEffect(.replace))
            case .opacity: content.contentTransition(.opacity)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Plays `haptic` whenever `trigger` changes and `condition` holds for its new value.
    func haptic<Trigger: Equatable>(
        _ haptic: Haptic,
        trigger: Trigger,
        when condition: @escaping (Trigger) -> Bool = { _ in true }
    ) -> some View {
        modifier(HapticModifier(haptic: haptic, trigger: trigger, condition: condition))
    }

    /// Bounces an SF Symbol each time `value` changes. iOS 17 and later; still on iOS 15.
    func symbolBounce<Value: Equatable>(value: Value, down: Bool = false) -> some View {
        modifier(SymbolBounceModifier(value: value, down: down))
    }

    /// Morphs one SF Symbol into the next (play ↔ pause). iOS 17 and later; a plain swap on iOS 15.
    func symbolReplaceTransition() -> some View {
        modifier(ContentTransitionModifier(kind: .symbolReplace))
    }

    /// Cross-fades changing text. iOS 17 and later; a plain swap on iOS 15.
    func opacityContentTransition() -> some View {
        modifier(ContentTransitionModifier(kind: .opacity))
    }
}

// MARK: - Accessibility traits

extension View {
    /// `.isToggle` where it exists (iOS 17), otherwise `.isButton`.
    @ViewBuilder
    func accessibilityToggleTrait() -> some View {
        if #available(iOS 17.0, *) {
            accessibilityAddTraits(.isToggle)
        } else {
            accessibilityAddTraits(.isButton)
        }
    }

    /// `.isTabBar` where it exists (iOS 17).
    @ViewBuilder
    func accessibilityTabBarTrait() -> some View {
        if #available(iOS 17.0, *) {
            accessibilityAddTraits(.isTabBar)
        } else {
            self
        }
    }
}

// MARK: - Scrolling and bars

extension View {
    /// Hides the navigation bar on pages that draw their own header.
    @ViewBuilder
    func hidesNavigationBar() -> some View {
        if #available(iOS 16.0, *), !DeviceProfile.usesLegacyUI {
            toolbar(.hidden, for: .navigationBar)
        } else {
            navigationBarHidden(true)
        }
    }

    /// Colours the navigation bar (iOS 16 and later). iOS 15 keeps the system bar, which is
    /// clear at the top of a page and frosted once it scrolls.
    @ViewBuilder
    func navigationBarBackground(_ color: Color, visibility: Visibility = .automatic) -> some View {
        if #available(iOS 16.0, *), !DeviceProfile.usesLegacyUI {
            toolbarBackground(color, for: .navigationBar)
                .toolbarBackground(visibility, for: .navigationBar)
        } else {
            self
        }
    }

    /// Dismisses the keyboard as soon as the page scrolls. On iOS 15 scroll views dismiss it on
    /// drag (see `LegacyAppearance`).
    @ViewBuilder
    func dismissesKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *), !DeviceProfile.usesLegacyUI {
            scrollDismissesKeyboard(.immediately)
        } else {
            self
        }
    }

    /// Bounces only when the content is taller than the scroll view (iOS 16.4 and later).
    @ViewBuilder
    func bouncesOnlyWhenScrollable() -> some View {
        if #available(iOS 16.4, *), !DeviceProfile.usesLegacyUI {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

/// System-wide UIKit settings for the iOS 15 paths, applied once at launch.
enum LegacyAppearance {
    @MainActor
    static func apply() {
        guard DeviceProfile.usesLegacyUI else { return }
        // iOS 15 has no `scrollDismissesKeyboard`: scrolling a page dismisses the keyboard.
        UIScrollView.appearance().keyboardDismissMode = .onDrag
        // The back button and bar buttons in NavigationView follow the window tint, not `.tint`.
        UINavigationBar.appearance().tintColor = UIColor(Theme.accent)
    }
}

// MARK: - Navigation

/// `NavigationStack` on iOS 16 and later, a stack-style `NavigationView` on iOS 15. For sheets
/// and other stacks that never push routes.
struct CompatNavigationStack<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *), !DeviceProfile.usesLegacyUI {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

/// A tab's navigation stack driven by a `[Route]` path. iOS 16 and later use `NavigationStack`;
/// iOS 15 chains hidden `NavigationLink`s, one per route in the path, so pushing, popping and
/// popping to the root all go through the same path either way.
struct RouteNavigationStack<Root: View, Destination: View>: View {
    @Binding var path: [Route]
    private let root: Root
    private let destination: (Route) -> Destination

    init(path: Binding<[Route]>, @ViewBuilder root: () -> Root, @ViewBuilder destination: @escaping (Route) -> Destination) {
        _path = path
        self.root = root()
        self.destination = destination
    }

    var body: some View {
        if #available(iOS 16.0, *), !DeviceProfile.usesLegacyUI {
            NavigationStack(path: $path) {
                root.navigationDestination(for: Route.self) { route in
                    destination(route)
                }
            }
        } else {
            NavigationView {
                root.background(LegacyRouteLink(path: $path, index: 0, destination: destination))
            }
            .navigationViewStyle(.stack)
        }
    }
}

/// The iOS 15 link for `path[index]`. Its destination carries the link for the next index.
private struct LegacyRouteLink<Destination: View>: View {
    @Binding var path: [Route]
    let index: Int
    let destination: (Route) -> Destination

    /// The route this level showed last, so the page still draws while it slides away after a
    /// pop has already removed it from the path.
    @State private var lastRoute: Route?

    private var route: Route? { index < path.count ? path[index] : nil }

    var body: some View {
        NavigationLink(destination: destinationView, isActive: isActive) {
            EmptyView()
        }
        .hidden()
        .accessibilityHidden(true)
        .onAppear { if let route { lastRoute = route } }
        .onChange(of: route) { newRoute in
            if let newRoute { lastRoute = newRoute }
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        if let shown = route ?? lastRoute {
            destination(shown)
                .background(LegacyRouteLink(path: $path, index: index + 1, destination: destination))
        }
    }

    private var isActive: Binding<Bool> {
        Binding(
            get: { index < path.count },
            set: { isActive in
                // Back button or swipe back: drop this route and everything above it.
                if !isActive, index < path.count {
                    path.removeSubrange(index...)
                }
            }
        )
    }
}

// MARK: - Sheets

/// How tall a sheet can be.
enum SheetDetent: Hashable {
    case medium
    case large
    /// Exactly this tall. iOS 15 rounds it to medium or large.
    case height(CGFloat)
}

private struct EmberSheetModifier: ViewModifier {
    let detents: [SheetDetent]?
    let showsGrabber: Bool
    let background: Color
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *), !DeviceProfile.usesLegacyUI {
            content
                .presentationDetents(Set((detents ?? [.large]).map(\.presentationDetent)))
                .presentationDragIndicator(showsGrabber ? .visible : .automatic)
                .presentationBackground(background)
                .presentationCornerRadius(cornerRadius)
        } else {
            content
                .background(background)
                .background(SheetPresentationConfigurator(
                    detents: detents.map(Self.legacyDetents),
                    showsGrabber: showsGrabber,
                    cornerRadius: cornerRadius
                ))
        }
    }

    /// iOS 15 only has medium (about half the screen) and large.
    private static func legacyDetents(_ detents: [SheetDetent]) -> [SheetDetent] {
        let halfScreen = UIScreen.main.bounds.height * 0.45
        var medium = false
        var large = false
        for detent in detents {
            switch detent {
            case .medium: medium = true
            case .large: large = true
            case .height(let height):
                // Short content opens at half height and can still be pulled up.
                if height <= halfScreen { medium = true }
                large = true
            }
        }
        var result: [SheetDetent] = []
        if medium { result.append(.medium) }
        if large || result.isEmpty { result.append(.large) }
        return result
    }
}

@available(iOS 16.0, *)
private extension SheetDetent {
    var presentationDetent: PresentationDetent {
        switch self {
        case .medium: return .medium
        case .large: return .large
        case .height(let height): return .height(height)
        }
    }
}

/// Reaches the UIKit sheet that presents this SwiftUI content and sets its detents, grabber and
/// corner radius: what `presentationDetents` and friends do on iOS 16 and later.
private struct SheetPresentationConfigurator: UIViewControllerRepresentable {
    /// `.medium` and `.large` only.
    let detents: [SheetDetent]?
    let showsGrabber: Bool
    let cornerRadius: CGFloat?

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.detents = detents
        controller.showsGrabber = showsGrabber
        controller.cornerRadius = cornerRadius
        controller.apply()
    }

    final class Controller: UIViewController {
        var detents: [SheetDetent]?
        var showsGrabber = false
        var cornerRadius: CGFloat?
        /// What was last handed to the sheet, so unchanged detents aren't set again.
        private var appliedDetents: [SheetDetent]?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        func apply() {
            guard let sheet = presentedAncestor()?.sheetPresentationController else { return }
            let isOnScreen = viewIfLoaded?.window != nil
            let update = { [self] in
                if let detents, detents != appliedDetents {
                    sheet.detents = detents.map { $0 == .medium ? .medium() : .large() }
                    appliedDetents = detents
                }
                sheet.prefersGrabberVisible = showsGrabber
                if let cornerRadius { sheet.preferredCornerRadius = cornerRadius }
            }
            if isOnScreen {
                sheet.animateChanges(update)
            } else {
                update()
            }
        }

        /// The controller the sheet presents: the top of this controller's parent chain.
        private func presentedAncestor() -> UIViewController? {
            var controller: UIViewController = self
            while let parent = controller.parent { controller = parent }
            return controller.presentingViewController == nil ? nil : controller
        }
    }
}

private struct FittedSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Sheet chrome: detents, grabber, background and corner radius. On iOS 15 it goes through
    /// UIKit's sheet controller (medium and large only) and the background sits behind the content.
    func emberSheet(
        detents: [SheetDetent]? = nil,
        showsGrabber: Bool = false,
        background: Color,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        modifier(EmberSheetModifier(detents: detents, showsGrabber: showsGrabber, background: background, cornerRadius: cornerRadius))
    }

    /// Reports this view's height through `FittedSheetHeightKey`. Works on every iOS version,
    /// unlike `onGeometryChange` (iOS 16).
    func reportsFittedSheetHeight(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: FittedSheetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(FittedSheetHeightKey.self, perform: action)
    }
}

// MARK: - Animation and time

/// Runs `body` with `animation`, then `completion` once it has settled. iOS 17 waits for the
/// animation itself; iOS 15 waits `duration`.
@MainActor
func animate(_ animation: Animation, duration: TimeInterval, _ body: () -> Void, completion: @escaping @MainActor @Sendable () -> Void) {
    if #available(iOS 17.0, *), !DeviceProfile.usesLegacyUI {
        withAnimation(animation, body, completion: completion)
    } else {
        withAnimation(animation, body)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
    }
}

extension Task where Success == Never, Failure == Never {
    /// `Task.sleep(for:)` without `Duration`, which is iOS 16 and later.
    static func sleep(seconds: Double) async throws {
        try await sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
    }
}
