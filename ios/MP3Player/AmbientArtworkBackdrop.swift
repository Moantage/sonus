import SwiftUI

/// The song's artwork, blown up and blurred into light, slowly turning while music plays.
/// A dark wash at the bottom keeps the controls readable on any artwork. Still when paused or
/// when Reduce Motion is on.
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
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .drawingGroup()
                }
                .blur(radius: 70)
                .saturation(1.25)
                .opacity(0.9)
                .id(songID)
                .transition(.opacity)

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
