import Foundation

/// The equaliser's state: on or off, and one gain per band, in dB.
///
/// Six peaking bands, like the equalisers people already know from big streaming apps. Gains are
/// clamped to ±``maxGain``. Boosts are paid for with ``headroomDB`` of automatic gain reduction
/// so a boosted song doesn't clip.
public struct EqualizerSettings: Codable, Equatable, Hashable, Sendable {
    /// Centre frequencies in Hz.
    public static let frequencies: [Double] = [60, 150, 400, 1000, 2400, 15000]
    public static var bandCount: Int { frequencies.count }
    public static let maxGain: Float = 12

    public var isEnabled: Bool
    /// One gain per band in dB, low to high.
    public var gains: [Float]
    /// The preset these gains came from, or nil once the person moves a slider themselves.
    public var presetID: String?

    public init(isEnabled: Bool = false, gains: [Float] = Array(repeating: 0, count: 6), presetID: String? = nil) {
        self.isEnabled = isEnabled
        self.gains = Self.clamped(gains)
        self.presetID = presetID
    }

    /// Off, with every band at 0 dB.
    public static let off = EqualizerSettings()

    /// True when every band is at 0 dB, so processing would change nothing.
    public var isFlat: Bool {
        gains.allSatisfy { abs($0) < 0.05 }
    }

    /// Whether audio needs processing at all.
    public var isActive: Bool {
        isEnabled && !isFlat
    }

    /// Gain reduction applied before the bands: the largest boost, so the loudest band ends up
    /// near 0 dB and boosted songs don't clip. Always ≤ 0.
    public var headroomDB: Float {
        -max(0, gains.max() ?? 0)
    }

    /// These settings with `preset`'s gains, switched on.
    public func applying(_ preset: EqualizerPreset) -> EqualizerSettings {
        EqualizerSettings(isEnabled: true, gains: preset.gains, presetID: preset.id)
    }

    /// These settings with one band changed by hand; the preset no longer applies.
    public func settingGain(_ gain: Float, forBand band: Int) -> EqualizerSettings {
        guard gains.indices.contains(band) else { return self }
        var copy = self
        copy.gains[band] = Self.clamp(gain)
        copy.presetID = nil
        return copy
    }

    /// The preset currently in use, if the gains still match one.
    public var preset: EqualizerPreset? {
        presetID.flatMap { id in EqualizerPreset.all.first { $0.id == id } }
    }

    // MARK: - Coding

    enum CodingKeys: String, CodingKey {
        case isEnabled, gains, presetID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        gains = Self.clamped(try container.decodeIfPresent([Float].self, forKey: .gains) ?? [])
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
    }

    /// Exactly ``bandCount`` finite gains within ±``maxGain``.
    static func clamped(_ gains: [Float]) -> [Float] {
        (0..<bandCount).map { index in
            index < gains.count ? clamp(gains[index]) : 0
        }
    }

    static func clamp(_ gain: Float) -> Float {
        guard gain.isFinite else { return 0 }
        return min(maxGain, max(-maxGain, gain))
    }
}

/// A named set of band gains.
public struct EqualizerPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Gains in dB for 60, 150, 400, 1k, 2.4k and 15k Hz.
    public let gains: [Float]

    public static let flat = EqualizerPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0])

    public static let all: [EqualizerPreset] = [
        flat,
        EqualizerPreset(id: "bass-boost", name: "Bass boost", gains: [6, 4.5, 1.5, 0, 0, 0]),
        EqualizerPreset(id: "bass-cut", name: "Bass cut", gains: [-6, -4.5, -1.5, 0, 0, 0]),
        EqualizerPreset(id: "treble-boost", name: "Treble boost", gains: [0, 0, 0, 1, 4, 6]),
        EqualizerPreset(id: "vocal", name: "Vocal", gains: [-2, -1, 1.5, 3.5, 3, 0]),
        EqualizerPreset(id: "acoustic", name: "Acoustic", gains: [3, 2, 0, 1, 2.5, 3]),
        EqualizerPreset(id: "electronic", name: "Electronic", gains: [5, 3.5, -1, 0, 2, 4.5]),
        EqualizerPreset(id: "rock", name: "Rock", gains: [4, 2.5, -1.5, 0.5, 2.5, 4]),
        EqualizerPreset(id: "late-night", name: "Late night", gains: [-3, -1, 1, 2, 1, -3])
    ]
}

/// Coefficients of one second-order (biquad) filter, normalised so the first feedback term is 1.
/// In textbook terms, `forward0...2` are b0...b2 and `back1...2` are a1...a2.
public struct BiquadCoefficients: Equatable, Sendable {
    public var forward0: Double, forward1: Double, forward2: Double, back1: Double, back2: Double

    public static let identity = BiquadCoefficients(forward0: 1, forward1: 0, forward2: 0, back1: 0, back2: 0)

    /// The bandwidth of each band. 1.0 is a little over an octave and a third, so neighbouring
    /// bands blend smoothly.
    public static let bandQ = 1.0

    /// A peaking filter (Robert Bristow-Johnson's Audio EQ Cookbook). The frequency is kept below
    /// 45% of the sample rate so a 15 kHz band stays stable on low sample rates.
    public static func peaking(frequency: Double, gainDB: Double, quality: Double = bandQ, sampleRate: Double) -> BiquadCoefficients {
        guard abs(gainDB) > 0.001, sampleRate > 0 else { return .identity }
        let safeFrequency = min(frequency, sampleRate * 0.45)
        let amplitude = pow(10, gainDB / 40)
        let omega = 2 * Double.pi * safeFrequency / sampleRate
        let alpha = sin(omega) / (2 * quality)
        let cosine = cos(omega)
        let norm = 1 + alpha / amplitude
        return BiquadCoefficients(
            forward0: (1 + alpha * amplitude) / norm,
            forward1: (-2 * cosine) / norm,
            forward2: (1 - alpha * amplitude) / norm,
            back1: (-2 * cosine) / norm,
            back2: (1 - alpha / amplitude) / norm
        )
    }

    /// The filter's gain at `frequency`, in dB.
    public func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let cos1 = cos(omega), sin1 = sin(omega)
        let cos2 = cos(2 * omega), sin2 = sin(2 * omega)
        let numeratorReal = forward0 + forward1 * cos1 + forward2 * cos2
        let numeratorImaginary = -(forward1 * sin1 + forward2 * sin2)
        let denominatorReal = 1 + back1 * cos1 + back2 * cos2
        let denominatorImaginary = -(back1 * sin1 + back2 * sin2)
        let numerator = numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary
        let denominator = denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary
        guard numerator > 0, denominator > 0 else { return -120 }
        return 10 * log10(numerator / denominator)
    }
}

/// The equaliser's overall frequency response, for drawing its curve.
public enum EqualizerResponse {
    /// Gain in dB at `frequency` for `settings`. The curve people see leaves out the headroom,
    /// so a bass boost looks like a boost rather than everything else dropping.
    public static func gainDB(at frequency: Double, settings: EqualizerSettings, sampleRate: Double = 44100,
                              includingHeadroom: Bool = false) -> Double {
        guard settings.isEnabled else { return 0 }
        var total = includingHeadroom ? Double(settings.headroomDB) : 0
        for (band, centre) in EqualizerSettings.frequencies.enumerated() {
            let filter = BiquadCoefficients.peaking(frequency: centre, gainDB: Double(settings.gains[band]), sampleRate: sampleRate)
            total += filter.magnitudeDB(at: frequency, sampleRate: sampleRate)
        }
        return total
    }

    /// `count` points from 20 Hz to 20 kHz, spaced evenly on a log scale, as (frequency, dB).
    public static func curve(for settings: EqualizerSettings, points count: Int = 96,
                             sampleRate: Double = 44100) -> [(frequency: Double, gainDB: Double)] {
        guard count > 1 else { return [] }
        let low = log10(20.0), high = log10(20000.0)
        return (0..<count).map { index in
            let frequency = pow(10, low + (high - low) * Double(index) / Double(count - 1))
            return (frequency, gainDB(at: frequency, settings: settings, sampleRate: sampleRate))
        }
    }
}
