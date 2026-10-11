import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Warm placeholder artwork and artwork-derived tints.
enum ArtworkPalette {
    /// Ember-family gradients for songs and playlists without artwork.
    private static let gradients: [(UInt, UInt)] = [
        (0xE8B15E, 0xC77D4A),
        (0xC77D4A, 0x8E3B2A),
        (0xD9A441, 0x6E5A2B),
        (0xB86B5A, 0x5A2E3A),
        (0xCDB48E, 0x6B5034),
        (0xD0643C, 0x4A2516)
    ]

    /// A stable index derived from the UUID bytes (`hashValue` changes on every launch).
    static func index(for id: UUID) -> Int {
        let bytes = id.uuid
        let mixed = Int(bytes.0) &+ Int(bytes.5) &* 3 &+ Int(bytes.10) &* 7 &+ Int(bytes.15) &* 11
        return mixed % gradients.count
    }

    static func gradient(for id: UUID) -> LinearGradient {
        let pair = gradients[index(for: id)]
        return LinearGradient(
            colors: [Color(hex: pair.0), Color(hex: pair.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Base colour of a placeholder, used to tint backgrounds when a song has no artwork.
    static func baseColor(for id: UUID) -> UIColor {
        let hex = gradients[index(for: id)].0
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

/// Placeholder artwork for a song: a warm gradient with a note glyph. Real artwork, when the
/// engine provides it, is passed as `image`.
struct SongArtwork: View {
    let id: UUID
    var image: UIImage?
    var size: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ArtworkPalette.gradient(for: id)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Theme.accentInk.opacity(0.45))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
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
                symbolTile("music.note.list", gradient: Theme.artworkGradient)
            case .recentlyAdded:
                symbolTile("clock.fill", gradient: ArtworkPalette.gradient(for: Self.recentID))
            case .downloaded:
                symbolTile("arrow.down.circle.fill", gradient: ArtworkPalette.gradient(for: Self.downloadedID))
            case .playlist(let id):
                if songs.count >= 4 {
                    mosaic
                } else if let first = songs.first {
                    SongArtwork(id: first.id, size: size, cornerRadius: 0)
                } else {
                    symbolTile("music.note", gradient: ArtworkPalette.gradient(for: id), muted: true)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.artwork, style: .continuous))
        .accessibilityHidden(true)
    }

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

    private func symbolTile(_ symbol: String, gradient: LinearGradient, muted: Bool = false) -> some View {
        ZStack {
            if muted {
                Theme.surfaceRaised
            } else {
                gradient
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(muted ? Theme.textSubtle : Theme.accentInk.opacity(0.8))
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
