import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Generated cover art and artwork-derived tints.
enum ArtworkPalette {
    /// One cover palette: a light and a deep stop for the base gradient, and a glow for the
    /// soft light and the motif. Mostly Ember warms, with two dusk tones so a library of
    /// covers never looks like one colour.
    struct Swatch {
        let light: UInt
        let deep: UInt
        let glow: UInt
    }

    static let swatches: [Swatch] = [
        Swatch(light: 0xE8B15E, deep: 0x9A4F2C, glow: 0xFFE2A8),   // amber → copper
        Swatch(light: 0xC77D4A, deep: 0x4A1C17, glow: 0xF6A86E),   // copper → oxblood
        Swatch(light: 0xD9A441, deep: 0x3F3A1C, glow: 0xF8DA88),   // gold → olive
        Swatch(light: 0xC8786A, deep: 0x3A1D36, glow: 0xF5B198),   // rose → plum
        Swatch(light: 0xD8C3A0, deep: 0x5A4330, glow: 0xFFF3DC),   // sand → umber
        Swatch(light: 0xD0643C, deep: 0x2E140C, glow: 0xFFB46E),   // ember → char
        Swatch(light: 0x5C8A86, deep: 0x15232A, glow: 0xE8B15E),   // dusk teal, amber sun
        Swatch(light: 0x8E7BAE, deep: 0x231B36, glow: 0xF0C77E)    // lavender dusk
    ]

    /// A stable index derived from the UUID bytes (`hashValue` changes on every launch).
    static func index(for id: UUID) -> Int {
        let bytes = id.uuid
        let mixed = Int(bytes.0) &+ Int(bytes.5) &* 3 &+ Int(bytes.10) &* 7 &+ Int(bytes.15) &* 11
        return mixed % swatches.count
    }

    static func swatch(for id: UUID) -> Swatch {
        swatches[index(for: id)]
    }

    static func gradient(for id: UUID) -> LinearGradient {
        let swatch = swatch(for: id)
        return LinearGradient(
            colors: [Color(hex: swatch.light), Color(hex: swatch.deep)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Base colour of a generated cover, used to tint backgrounds when a song has no artwork.
    static func baseColor(for id: UUID) -> UIColor {
        let hex = swatch(for: id).light
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// The average colour of an image (Core Image area average, rendered to one pixel).
    static func averageColor(of image: UIImage) -> UIColor? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    /// Turns any colour into a backdrop that keeps cream text readable: same hue, moderate
    /// saturation, brightness held in a dark band.
    static func backdrop(from color: UIColor, brightness range: ClosedRange<CGFloat> = 0.26...0.42) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return Theme.backgroundElevated
        }
        let clampedSaturation = min(max(saturation, 0.18), 0.68)
        let clampedBrightness = min(max(brightness * 0.75, range.lowerBound), range.upperBound)
        return Color(hue: hue, saturation: clampedSaturation, brightness: clampedBrightness)
    }
}

/// A song's artwork: the real image when the engine has one, otherwise its generated cover.
struct SongArtwork: View {
    let id: UUID
    var image: UIImage?
    var size: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                GenerativeCover(id: id)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            // A hairline keeps dark covers from melting into the background.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Cover art drawn from a song's ID, so a library without artwork still looks like a shelf of
/// records: a two-stop gradient, soft light, and one of four motifs (rings, waves, a setting
/// sun, equaliser bars). The same ID always draws the same cover.
struct GenerativeCover: View {
    let id: UUID
    /// Off for tiles that carry their own glyph (All songs, Downloaded), so the two don't clash.
    var showsMotif = true

    private enum Motif: CaseIterable {
        case rings, waves, sun, bars
    }

    var body: some View {
        Canvas { context, size in
            var random = SeededRandom(id: id)
            let swatch = ArtworkPalette.swatch(for: id)
            let light = Color(hex: swatch.light)
            let deep = Color(hex: swatch.deep)
            let glow = Color(hex: swatch.glow)
            let rect = CGRect(origin: .zero, size: size)
            let side = min(size.width, size.height)

            let angle = random.next(in: 0...(2 * .pi))
            let start = CGPoint(x: rect.midX + cos(angle) * side * 0.7, y: rect.midY + sin(angle) * side * 0.7)
            let end = CGPoint(x: rect.midX - cos(angle) * side * 0.7, y: rect.midY - sin(angle) * side * 0.7)
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: [light, deep]), startPoint: start, endPoint: end))

            // Soft light.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: side * 0.16))
                for _ in 0..<2 {
                    let radius = side * random.next(in: 0.28...0.5)
                    let center = CGPoint(x: side * random.next(in: 0.1...0.9), y: side * random.next(in: 0.1...0.9))
                    let orb = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    layer.fill(Path(ellipseIn: orb), with: .color(glow.opacity(random.next(in: 0.35...0.6))))
                }
            }

            let motif = Motif.allCases[Int(random.next(in: 0...3.99))]
            switch showsMotif ? motif : nil {
            case .rings:
                let center = CGPoint(x: side * random.next(in: 0.3...0.7), y: side * random.next(in: 0.3...0.7))
                for ring in 1...7 {
                    let radius = side * 0.09 * CGFloat(ring)
                    let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: circle), with: .color(.white.opacity(0.16)), lineWidth: max(side * 0.006, 0.5))
                }
                let label = side * 0.07
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - label, y: center.y - label, width: label * 2, height: label * 2)),
                    with: .color(glow.opacity(0.85))
                )
            case .waves:
                let amplitude = side * random.next(in: 0.03...0.07)
                let frequency = random.next(in: 1.2...2.6)
                let phase = random.next(in: 0...(2 * .pi))
                for line in 0..<6 {
                    let baseline = side * (0.4 + CGFloat(line) * 0.09)
                    var path = Path()
                    for step in 0...40 {
                        let x = side * CGFloat(step) / 40
                        let y = baseline + sin(x / side * frequency * 2 * .pi + phase + CGFloat(line) * 0.5) * amplitude
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path, with: .color(.white.opacity(0.1 + Double(line) * 0.03)), lineWidth: max(side * 0.008, 0.6))
                }
            case .sun:
                let radius = side * random.next(in: 0.2...0.3)
                let horizon = side * random.next(in: 0.58...0.7)
                let center = CGPoint(x: side * random.next(in: 0.35...0.65), y: horizon)
                var sun = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                sun = sun.intersection(Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
                context.fill(sun, with: .linearGradient(
                    Gradient(colors: [glow, glow.opacity(0.55)]),
                    startPoint: CGPoint(x: center.x, y: center.y - radius),
                    endPoint: CGPoint(x: center.x, y: horizon)
                ))
                for stripe in 0..<4 {
                    let y = horizon + side * 0.05 * CGFloat(stripe + 1)
                    let width = side * (0.5 - CGFloat(stripe) * 0.08)
                    let bar = CGRect(x: center.x - width / 2, y: y, width: width, height: max(side * 0.012, 0.6))
                    let opacity = 0.45 - Double(stripe) * 0.08
                    context.fill(Path(roundedRect: bar, cornerRadius: bar.height / 2), with: .color(glow.opacity(opacity)))
                }
            case .bars:
                let count = 7
                let gap = side * 0.035
                let barWidth = (side * 0.62 - gap * CGFloat(count - 1)) / CGFloat(count)
                let originX = side * 0.19
                let bottom = side * 0.78
                for bar in 0..<count {
                    let height = side * random.next(in: 0.12...0.5)
                    let frame = CGRect(x: originX + CGFloat(bar) * (barWidth + gap), y: bottom - height, width: barWidth, height: height)
                    let opacity = random.next(in: 0.5...0.9)
                    context.fill(Path(roundedRect: frame, cornerRadius: barWidth / 2), with: .color(glow.opacity(opacity)))
                }
            case nil:
                break
            }

            // Depth: a gentle vignette towards the bottom.
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [.clear, .black.opacity(0.22)]),
                startPoint: CGPoint(x: 0, y: rect.midY),
                endPoint: CGPoint(x: 0, y: rect.maxY)
            ))
        }
        .accessibilityHidden(true)
    }
}

/// A tiny deterministic generator (SplitMix64) seeded from a UUID, so covers are stable.
private struct SeededRandom {
    private var state: UInt64

    init(id: UUID) {
        let bytes = id.uuid
        let high = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
        let low = [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]
        let fold = { (values: [UInt8]) in values.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } }
        state = fold(high) ^ fold(low)
    }

    mutating func nextUInt() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(nextUInt() >> 11) / CGFloat(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

/// Square artwork that fills the width it's given (Now Playing, collection headers).
struct FlexibleArtwork: View {
    let id: UUID
    var image: UIImage?
    var cornerRadius: CGFloat = Theme.Radius.card

    var body: some View {
        GeometryReader { proxy in
            SongArtwork(id: id, image: image, size: min(proxy.size.width, proxy.size.height), cornerRadius: cornerRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Artwork for a collection: a 2×2 mosaic of its first songs, or a single tile.
struct CollectionArtwork: View {
    let collection: SongCollection
    let songs: [Song]
    var size: CGFloat

    var body: some View {
        Group {
            switch collection {
            case .allSongs:
                symbolTile("music.note.list", seed: Self.allSongsID)
            case .recentlyAdded:
                symbolTile("clock.fill", seed: Self.recentID)
            case .downloaded:
                symbolTile("arrow.down.circle.fill", seed: Self.downloadedID)
            case .playlist(let id):
                if songs.count >= 4 {
                    mosaic
                } else if let first = songs.first {
                    SongArtwork(id: first.id, size: size, cornerRadius: 0)
                } else {
                    symbolTile("music.note", seed: id, muted: true)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous))
        .accessibilityHidden(true)
    }

    private static let allSongsID = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
    private static let recentID = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
    private static let downloadedID = UUID(uuidString: "00000000-0000-0000-0000-000000000004") ?? UUID()

    private var mosaic: some View {
        let half = size / 2
        let tiles = Array(songs.prefix(4))
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                SongArtwork(id: tiles[0].id, size: half, cornerRadius: 0)
                SongArtwork(id: tiles[1].id, size: half, cornerRadius: 0)
            }
            HStack(spacing: 0) {
                SongArtwork(id: tiles[2].id, size: half, cornerRadius: 0)
                SongArtwork(id: tiles[3].id, size: half, cornerRadius: 0)
            }
        }
    }

    private func symbolTile(_ symbol: String, seed: UUID, muted: Bool = false) -> some View {
        ZStack {
            if muted {
                Theme.surfaceRaised
            } else {
                GenerativeCover(id: seed, showsMotif: false)
                Color.black.opacity(0.08)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(muted ? Theme.textSubtle : Theme.textPrimary)
                .shadow(color: .black.opacity(muted ? 0 : 0.3), radius: size * 0.06, y: size * 0.02)
        }
    }
}

/// Animated equaliser bars shown next to the song that's playing. Static when paused or when
/// Reduce Motion is on.
struct EqualizerBars: View {
    var isAnimating: Bool
    var color: Color = Theme.accent
    var height: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isAnimating && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(at: nil)
        }
    }

    private func bars(at time: TimeInterval?) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: barHeight(index: index, time: time))
            }
        }
        .frame(width: 13, height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func barHeight(index: Int, time: TimeInterval?) -> CGFloat {
        guard let time else {
            return height * [0.45, 0.8, 0.6][index]
        }
        let speed = [5.1, 6.7, 4.3][index]
        let phase = [0.0, 1.3, 2.4][index]
        let wave = (sin(time * speed + phase) + 1) / 2
        return height * (0.25 + 0.75 * wave)
    }
}
