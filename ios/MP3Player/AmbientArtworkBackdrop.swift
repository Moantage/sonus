import SwiftUI

/// The song's artwork, blown up and blurred into light, slowly turning while music plays.
/// A dark wash at the bottom keeps the controls readable on any artwork. Still when paused or
/// when Reduce Motion is on.
///
/// Older hardware (iOS 15 devices such as the iPod touch) gets two soft glows in the artwork's
/// colour instead: re-blurring full-screen artwork costs dropped frames there, above all while
/// Now Playing grows out of the mini-player.
struct AmbientArtworkBackdrop: View {
    let songID: UUID?
    let image: UIImage?
    let tint: UIColor
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height) * 1.25
            ZStack {
                Color(uiColor: tint).opacity(0.35)

                if DeviceProfile.prefersLightEffects {
                    tintGlow(size: proxy.size)
                } else {
                    blurredArtwork(size: proxy.size, side: side)
                }

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.2), location: 0),
                        .init(color: .black.opacity(0.05), location: 0.35),
                        .init(color: Theme.backgroundBase.opacity(0.75), location: 0.72),
                        .init(color: Theme.backgroundBase.opacity(0.95), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .animation(.easeInOut(duration: 0.8), value: songID)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func blurredArtwork(size: CGSize, side: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let drift = reduceMotion ? 0 : time
            ZStack {
                artwork(side: side)
                    .rotationEffect(.degrees(drift.truncatingRemainder(dividingBy: 90) * 4))
                    .offset(x: -side * 0.18, y: -side * 0.22)
                artwork(side: side * 0.8)
                    .rotationEffect(.degrees(-drift.truncatingRemainder(dividingBy: 120) * 3))
                    .scaleEffect(x: -1)
                    .offset(x: side * 0.22, y: side * 0.1)
                    .opacity(0.8)
            }
            .frame(width: size.width, height: size.height)
            .drawingGroup()
        }
        .blur(radius: 70)
        .saturation(1.25)
        .opacity(0.9)
        .id(songID)
        .transition(.opacity)
    }

    /// Gradients only, no blur: cheap enough to animate on an A10.
    private func tintGlow(size: CGSize) -> some View {
        let color = ArtworkPalette.backdrop(from: tint, brightness: 0.42...0.62)
        let radius = max(size.width, size.height) * 0.75
        return ZStack {
            RadialGradient(
                colors: [color.opacity(0.9), color.opacity(0)],
                center: UnitPoint(x: 0.2, y: 0.12),
                startRadius: 0,
                endRadius: radius
            )
            RadialGradient(
                colors: [color.opacity(0.55), color.opacity(0)],
                center: UnitPoint(x: 0.9, y: 0.45),
                startRadius: 0,
                endRadius: radius * 0.7
            )
        }
        .id(songID)
        .transition(.opacity)
    }

    @ViewBuilder
    private func artwork(side: CGFloat) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(Circle())
        } else if let songID {
            GenerativeCover(id: songID)
                .frame(width: side, height: side)
                .clipShape(Circle())
        }
    }
}
