import Foundation

/// Runs the equaliser on audio as it plays: one biquad per band per channel, after a headroom gain.
///
/// Built for an audio render thread: ``update(_:)`` may be called from any thread at any time, and
/// the render side only *tries* the lock, so a settings change can never make audio wait. New
/// settings take effect at the start of the next block; the headroom gain ramps across that block
/// so moving a slider doesn't click, and switching on or off crossfades between the untouched and
/// the equalised sound over one block. Nothing allocates while processing.
///
/// Per block, call ``beginBlock(frameCount:)`` once, then ``process(_:frameCount:channelStride:firstChannel:)``
/// for each buffer (one call per channel for non-interleaved audio, or one call for interleaved).
public final class EqualizerProcessor: @unchecked Sendable {
    private let lock = NSLock()
    /// Settings waiting for the next block. Guarded by `lock`.
    private var pending: EqualizerSettings?

    // Render-side state: touched only by `prepare` and the render calls.
    private var settings: EqualizerSettings
    private var sampleRate: Double = 44100
    private var channelCount = 0
    private var coefficients = [BiquadCoefficients](repeating: .identity, count: EqualizerSettings.bandCount)
    /// Two delay values (z⁻¹, z⁻²) per band per channel, transposed direct form II.
    private var state: [Double] = []
    /// The headroom gain the settings ask for.
    private var targetGain: Float = 1
    /// This block ramps the gain from `rampFrom` to `rampTo`.
    private var rampFrom: Float = 1
    private var rampTo: Float = 1
    /// How much of the equalised signal is heard, ramped per block from `wetFrom` to `wetTo`.
    private var wetFrom: Float = 0
    private var wetTo: Float = 0
    private var isBypassed = true

    public init(settings: EqualizerSettings) {
        self.settings = settings
        rebuild()
        rampFrom = targetGain
        rampTo = targetGain
    }

    /// Hands new settings to the render side. Safe from any thread.
    public func update(_ settings: EqualizerSettings) {
        lock.lock()
        pending = settings
        lock.unlock()
    }

    /// Sets the format before rendering starts (or when it changes). Not for the render thread.
    public func prepare(sampleRate: Double, channelCount: Int) {
        lock.lock()
        if let pending {
            settings = pending
            self.pending = nil
        }
        lock.unlock()
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100
        self.channelCount = max(0, channelCount)
        state = [Double](repeating: 0, count: self.channelCount * EqualizerSettings.bandCount * 2)
        rebuild()
        rampFrom = targetGain
        rampTo = targetGain
        wetFrom = isBypassed ? 0 : 1
        wetTo = wetFrom
    }

    /// Picks up new settings, if any, and sets this block's gain ramp. Call once per block.
    public func beginBlock(frameCount: Int) {
        if lock.try() {
            if let next = pending {
                pending = nil
                lock.unlock()
                settings = next
                rebuild()
            } else {
                lock.unlock()
            }
        }
        rampFrom = rampTo
        rampTo = targetGain
        wetFrom = wetTo
        wetTo = isBypassed ? 0 : 1
        if wetFrom == 0 && wetTo > 0 {
            // Fading in from the untouched sound: start the filters from rest.
            for index in state.indices { state[index] = 0 }
        }
    }

    /// Processes `frameCount` frames in place. `channelStride` is the number of interleaved
    /// channels in this buffer (1 for non-interleaved audio); `firstChannel` is the index of its
    /// first channel across all buffers.
    public func process(_ samples: UnsafeMutablePointer<Float>, frameCount: Int, channelStride: Int = 1, firstChannel: Int = 0) {
        guard wetFrom > 0 || wetTo > 0, frameCount > 0, channelStride > 0 else { return }
        let bands = EqualizerSettings.bandCount
        let steps = Float(max(1, frameCount - 1))
        let gainStep = (rampTo - rampFrom) / steps
        let wetStep = (wetTo - wetFrom) / steps
        for offset in 0..<channelStride {
            let channel = firstChannel + offset
            guard channel < channelCount else { continue }
            let base = channel * bands * 2
            var gain = rampFrom
            var wet = wetFrom
            var index = offset
            for _ in 0..<frameCount {
                let dry = samples[index]
                var sample = Double(dry * gain)
                for band in 0..<bands {
                    let filter = coefficients[band]
                    let slot = base + band * 2
                    let output = filter.forward0 * sample + state[slot]
                    state[slot] = filter.forward1 * sample - filter.back1 * output + state[slot + 1]
                    state[slot + 1] = filter.forward2 * sample - filter.back2 * output
                    sample = output
                }
                samples[index] = dry + (Float(sample) - dry) * wet
                gain += gainStep
                wet += wetStep
                index += channelStride
            }
        }
    }

    /// Whether audio now passes through untouched (off, and any fade-out has finished).
    public var bypassed: Bool {
        isBypassed && wetTo == 0
    }

    // MARK: - Private

    private func rebuild() {
        isBypassed = !settings.isActive
        for (band, frequency) in EqualizerSettings.frequencies.enumerated() {
            coefficients[band] = BiquadCoefficients.peaking(
                frequency: frequency,
                gainDB: Double(settings.gains[band]),
                sampleRate: sampleRate
            )
        }
        // While fading out, keep the last gain so the equalised side fades without a jump.
        if !isBypassed {
            targetGain = Float(pow(10, Double(settings.headroomDB) / 20))
        }
    }
}
