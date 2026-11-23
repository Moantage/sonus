import Foundation
import Testing
@testable import SonusCore

@Suite("Equaliser settings and presets")
struct EqualizerSettingsTests {
    @Test("Gains are clamped, padded and stripped of non-numbers")
    func clamping() {
        let settings = EqualizerSettings(isEnabled: true, gains: [20, -30, .nan, 3])
        #expect(settings.gains == [12, -12, 0, 3, 0, 0])
    }

    @Test("Headroom pays for the largest boost only")
    func headroom() {
        #expect(EqualizerSettings(isEnabled: true, gains: [6, 2, 0, -4, 0, 0]).headroomDB == -6)
        #expect(EqualizerSettings(isEnabled: true, gains: [-6, -2, 0, -4, 0, 0]).headroomDB == 0)
    }

    @Test("Off or flat means nothing to process")
    func activity() {
        #expect(!EqualizerSettings.off.isActive)
        #expect(!EqualizerSettings(isEnabled: true).isActive)
        #expect(!EqualizerSettings(isEnabled: false, gains: [6, 0, 0, 0, 0, 0]).isActive)
        #expect(EqualizerSettings(isEnabled: true, gains: [6, 0, 0, 0, 0, 0]).isActive)
    }

    @Test("Choosing a preset switches the equaliser on; moving a slider makes it custom")
    func presets() throws {
        let bass = try #require(EqualizerPreset.all.first { $0.id == "bass-boost" })
        let applied = EqualizerSettings.off.applying(bass)
        #expect(applied.isEnabled)
        #expect(applied.gains == bass.gains)
        #expect(applied.preset == bass)

        let custom = applied.settingGain(2, forBand: 3)
        #expect(custom.presetID == nil)
        #expect(custom.gains[3] == 2)
        #expect(applied.settingGain(1, forBand: 9) == applied)
    }

    @Test("Every preset has a unique ID, six bands and stays within range")
    func presetTable() {
        #expect(Set(EqualizerPreset.all.map(\.id)).count == EqualizerPreset.all.count)
        for preset in EqualizerPreset.all {
            #expect(preset.gains.count == EqualizerSettings.bandCount)
            #expect(preset.gains.allSatisfy { abs($0) <= EqualizerSettings.maxGain })
        }
    }

    @Test("Settings survive JSON, and old or broken JSON decodes safely")
    func coding() throws {
        let settings = EqualizerSettings(isEnabled: true, gains: [1, 2, 3, 4, 5, 6], presetID: "rock")
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(EqualizerSettings.self, from: data) == settings)

        let short = try JSONDecoder().decode(EqualizerSettings.self, from: Data(#"{"isEnabled": true, "gains": [3]}"#.utf8))
        #expect(short.gains == [3, 0, 0, 0, 0, 0])
        #expect(try JSONDecoder().decode(EqualizerSettings.self, from: Data("{}".utf8)) == .off)
    }
}

@Suite("Equaliser filters")
struct EqualizerFilterTests {
    @Test("A peaking band reaches its gain at its centre", arguments: [44100.0, 48000.0])
    func centreGain(sampleRate: Double) {
        for frequency in EqualizerSettings.frequencies {
            for gain in [-12.0, -6, 3, 12] {
                let filter = BiquadCoefficients.peaking(frequency: frequency, gainDB: gain, sampleRate: sampleRate)
                #expect(abs(filter.magnitudeDB(at: frequency, sampleRate: sampleRate) - gain) < 0.01)
            }
        }
    }

    @Test("A band leaves frequencies far from it alone")
    func locality() {
        let filter = BiquadCoefficients.peaking(frequency: 60, gainDB: 12, sampleRate: 44100)
        #expect(abs(filter.magnitudeDB(at: 5000, sampleRate: 44100)) < 0.1)
    }

    @Test("0 dB is an exact pass-through")
    func identity() {
        #expect(BiquadCoefficients.peaking(frequency: 1000, gainDB: 0, sampleRate: 44100) == .identity)
    }

    @Test("A 15 kHz band stays stable at a 22 kHz sample rate")
    func nyquist() {
        let filter = BiquadCoefficients.peaking(frequency: 15000, gainDB: 12, sampleRate: 22050)
        // Poles inside the unit circle: |back2| < 1 and |back1| < 1 + back2.
        #expect(abs(filter.back2) < 1)
        #expect(abs(filter.back1) < 1 + filter.back2)
    }

    @Test("The drawn curve shows the bands and ignores headroom")
    func curve() {
        let settings = EqualizerSettings(isEnabled: true, gains: [6, 0, 0, 0, 0, 0])
        #expect(abs(EqualizerResponse.gainDB(at: 60, settings: settings) - 6) < 0.2)
        #expect(abs(EqualizerResponse.gainDB(at: 60, settings: settings, includingHeadroom: true)) < 0.2)
        let points = EqualizerResponse.curve(for: settings, points: 50)
        #expect(points.count == 50)
        #expect(abs((points.first?.frequency ?? 0) - 20) < 0.001)
        #expect(abs((points.last?.frequency ?? 0) - 20000) < 0.01)
        #expect(EqualizerResponse.gainDB(at: 60, settings: .off) == 0)
    }
}

@Suite("Equaliser processing")
struct EqualizerProcessorTests {
    static let sampleRate = 44100.0

    /// A sine at `frequency`, `seconds` long, at amplitude 0.25, interleaved over `channels`.
    static func sine(_ frequency: Double, seconds: Double = 1, channels: Int = 1) -> [Float] {
        let frames = Int(sampleRate * seconds)
        var samples = [Float](repeating: 0, count: frames * channels)
        for frame in 0..<frames {
            let value = Float(0.25 * sin(2 * Double.pi * frequency * Double(frame) / sampleRate))
            for channel in 0..<channels {
                samples[frame * channels + channel] = value
            }
        }
        return samples
    }

    /// RMS level in dB of the second half (after the filters settle), for one channel.
    static func levelDB(_ samples: [Float], channels: Int = 1, channel: Int = 0) -> Double {
        let frames = samples.count / channels
        var sum = 0.0
        var count = 0
        for frame in (frames / 2)..<frames {
            let value = Double(samples[frame * channels + channel])
            sum += value * value
            count += 1
        }
        return 10 * log10(sum / Double(count))
    }

    /// Runs `samples` through `processor` in blocks of 512 frames.
    static func run(_ samples: inout [Float], through processor: EqualizerProcessor, channels: Int = 1) {
        let frames = samples.count / channels
        samples.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var start = 0
            while start < frames {
                let count = min(512, frames - start)
                processor.beginBlock(frameCount: count)
                processor.process(base + start * channels, frameCount: count, channelStride: channels)
                start += count
            }
        }
    }

    @Test("Off is bit-for-bit untouched")
    func bypass() {
        let processor = EqualizerProcessor(settings: .off)
        processor.prepare(sampleRate: Self.sampleRate, channelCount: 1)
        let input = Self.sine(440)
        var output = input
        Self.run(&output, through: processor)
        #expect(output == input)
        #expect(processor.bypassed)
    }

    @Test("A bass boost lifts bass relative to the mids, with headroom so nothing gets louder")
    func bassBoost() {
        let settings = EqualizerSettings(isEnabled: true, gains: [6, 0, 0, 0, 0, 0])
        let reference = Self.levelDB(Self.sine(60))

        let processor = EqualizerProcessor(settings: settings)
        processor.prepare(sampleRate: Self.sampleRate, channelCount: 1)
        var bass = Self.sine(60)
        Self.run(&bass, through: processor)

        let midProcessor = EqualizerProcessor(settings: settings)
        midProcessor.prepare(sampleRate: Self.sampleRate, channelCount: 1)
        var mid = Self.sine(5000)
        Self.run(&mid, through: midProcessor)

        // +6 dB at 60 Hz, then -6 dB headroom: 60 Hz stays where it was, 5 kHz drops 6 dB.
        #expect(abs(Self.levelDB(bass) - reference) < 0.3)
        #expect(abs(Self.levelDB(mid) - (reference - 6)) < 0.3)
        #expect(bass.allSatisfy { abs($0) <= 0.26 })
    }

    @Test("A cut lowers its band and needs no headroom")
    func cut() {
        let processor = EqualizerProcessor(settings: EqualizerSettings(isEnabled: true, gains: [0, 0, 0, -9, 0, 0]))
        processor.prepare(sampleRate: Self.sampleRate, channelCount: 1)
        var samples = Self.sine(1000)
        let reference = Self.levelDB(samples)
        Self.run(&samples, through: processor)
        #expect(abs(Self.levelDB(samples) - (reference - 9)) < 0.3)
    }

    @Test("Interleaved stereo gets the same result on both channels as mono does")
    func interleaved() {
        let settings = EqualizerSettings(isEnabled: true, gains: [0, 0, 0, 0, 6, 0])
        let mono = EqualizerProcessor(settings: settings)
        mono.prepare(sampleRate: Self.sampleRate, channelCount: 1)
        var monoSamples = Self.sine(2400)
        Self.run(&monoSamples, through: mono)

        let stereo = EqualizerProcessor(settings: settings)
        stereo.prepare(sampleRate: Self.sampleRate, channelCount: 2)
        var stereoSamples = Self.sine(2400, channels: 2)
        Self.run(&stereoSamples, through: stereo, channels: 2)

        let left = Self.levelDB(stereoSamples, channels: 2, channel: 0)
        let right = Self.levelDB(stereoSamples, channels: 2, channel: 1)
        #expect(abs(left - Self.levelDB(monoSamples)) < 0.001)
        #expect(abs(right - left) < 0.001)
    }

    @Test("New settings apply at the next block, and the gain ramps instead of jumping")
    func liveUpdate() {
        let processor = EqualizerProcessor(settings: .off)
        processor.prepare(sampleRate: Self.sampleRate, channelCount: 1)
        var first = [Float](repeating: 0.5, count: 512)
        Self.run(&first, through: processor)
        #expect(first.allSatisfy { $0 == 0.5 })

        // A cut-only setting with a boost elsewhere: headroom goes from 0 to -12 dB.
        processor.update(EqualizerSettings(isEnabled: true, gains: [0, 0, 0, 0, 0, 12]))
        var block = [Float](repeating: 0.5, count: 512)
        Self.run(&block, through: processor)
        #expect(!processor.bypassed)
        // The ramp starts near the old level and ends near the new one: no hard step.
        let jumps = zip(block, block.dropFirst()).map { abs($0 - $1) }
        #expect((jumps.max() ?? 1) < 0.01)
        #expect(abs(block[0] - 0.5) < 0.02)

        // Switching off fades back, then passes audio through exactly.
        processor.update(.off)
        var fadeOut = [Float](repeating: 0.5, count: 512)
        Self.run(&fadeOut, through: processor)
        #expect(abs((fadeOut.last ?? 0) - 0.5) < 0.001)
        #expect(processor.bypassed)
        var after = [Float](repeating: 0.5, count: 512)
        Self.run(&after, through: processor)
        #expect(after.allSatisfy { $0 == 0.5 })
    }

    @Test("Channels beyond the prepared count are left alone")
    func extraChannels() {
        let processor = EqualizerProcessor(settings: EqualizerSettings(isEnabled: true, gains: [0, 0, 0, -6, 0, 0]))
        processor.prepare(sampleRate: Self.sampleRate, channelCount: 1)
        var samples = [Float](repeating: 0.5, count: 64)
        samples.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            processor.beginBlock(frameCount: 64)
            processor.process(base, frameCount: 64, channelStride: 1, firstChannel: 1)
        }
        #expect(samples.allSatisfy { $0 == 0.5 })
    }
}
