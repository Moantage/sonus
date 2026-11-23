import AVFoundation
import MediaToolbox
import SonusCore

/// The equaliser's settings, and the audio taps that apply them.
///
/// Every player item gets an `MTAudioProcessingTap` in its audio mix, with its own
/// ``EqualizerProcessor`` (filters keep per-item state, so the current and preloaded songs can't
/// share one). The tap stays on even when the equaliser is off: it then passes audio through
/// untouched, and switching on mid-song crossfades in instead of rebuilding the item. Taps work on
/// local files and on progressive and `sonus-auth` streams alike. AVFoundation skips audio mixes on
/// AirPlay, so AirPlay plays without the equaliser.
@MainActor
final class EqualizerController: ObservableObject {
    static let shared = EqualizerController()

    private static let defaultsKey = "equalizer.settings"

    @Published private(set) var settings: EqualizerSettings

    /// Contexts of live taps, held weakly: each tap owns its context until AVFoundation releases it.
    private let contexts = NSHashTable<EqualizerTapContext>.weakObjects()

    init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(EqualizerSettings.self, from: data) {
            settings = saved
        } else {
            settings = .off
        }
        #if DEBUG
        startDebugLogging()
        #endif
    }

    // MARK: - Changing settings

    func setEnabled(_ enabled: Bool) {
        var next = settings
        next.isEnabled = enabled
        apply(next)
    }

    func choose(_ preset: EqualizerPreset) {
        apply(settings.applying(preset))
    }

    /// Moves one band. Moving a band switches the equaliser on: that's clearly what's wanted.
    func setGain(_ gain: Float, forBand band: Int) {
        var next = settings.settingGain(gain, forBand: band)
        next.isEnabled = true
        apply(next)
    }

    func reset() {
        apply(settings.applying(.flat))
    }

    private func apply(_ next: EqualizerSettings) {
        guard next != settings else { return }
        settings = next
        for context in contexts.allObjects {
            context.processor.update(next)
        }
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - Taps

    /// Gives `item` an audio mix with an equaliser tap, once its audio track is known. Playback
    /// doesn't wait for this; the tap joins as soon as the track has loaded.
    func attach(to item: AVPlayerItem) {
        let asset = item.asset
        Task { [weak item] in
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let item else { return }
            self.install(on: item, track: track)
        }
    }

    private func install(on item: AVPlayerItem, track: AVAssetTrack) {
        let context = EqualizerTapContext(processor: EqualizerProcessor(settings: settings))
        guard let tap = EqualizerTapContext.makeTap(for: context) else { return }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
        contexts.add(context)
    }

    #if DEBUG
    /// `-SonusDebugEqualizer`: logs, every two seconds, how much audio each tap processed and its
    /// input and output levels, so the equaliser can be checked without listening.
    private func startDebugLogging() {
        guard ProcessInfo.processInfo.arguments.contains("-SonusDebugEqualizer") else { return }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for context in self.contexts.allObjects {
                    let snapshot = context.takeDebugSnapshot()
                    guard snapshot.frames > 0 else { continue }
                    print(String(format: "[EQ] frames=%d in=%.1fdB out=%.1fdB float=%@ preset=%@ on=%@",
                                 snapshot.frames, snapshot.inputDB, snapshot.outputDB,
                                 context.isFloat ? "yes" : "no", self.settings.presetID ?? "custom",
                                 self.settings.isEnabled ? "yes" : "no"))
                }
            }
        }
    }
    #endif
}

/// What one tap needs on the audio thread: its processor and the stream format.
final class EqualizerTapContext: @unchecked Sendable {
    let processor: EqualizerProcessor
    /// Only 32-bit float PCM is processed; anything else passes through.
    fileprivate(set) var isFloat = false

    #if DEBUG
    // Written on the audio thread, read on the main thread for logging only.
    private var debugFrames = 0
    private var debugInput = 0.0
    private var debugOutput = 0.0
    #endif

    init(processor: EqualizerProcessor) {
        self.processor = processor
    }

    static func makeTap(for context: EqualizerTapContext) -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: { _, clientInfo, storageOut in
                // The tap keeps the retain taken above until `finalize`.
                storageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<EqualizerTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                let context = Unmanaged<EqualizerTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let description = format.pointee
                let isFloat = description.mFormatID == kAudioFormatLinearPCM
                    && description.mFormatFlags & kAudioFormatFlagIsFloat != 0
                    && description.mBitsPerChannel == 32
                context.isFloat = isFloat
                context.processor.prepare(sampleRate: description.mSampleRate,
                                          channelCount: isFloat ? Int(description.mChannelsPerFrame) : 0)
            },
            unprepare: nil,
            process: { tap, frameCount, _, bufferList, frameCountOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, frameCount, bufferList, flagsOut, nil, frameCountOut)
                guard status == noErr else { return }
                let context = Unmanaged<EqualizerTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.render(bufferList, frameCount: Int(frameCountOut.pointee))
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            // The tap never took ownership of the context.
            Unmanaged.passUnretained(context).release()
            return nil
        }
        return tap
    }

    /// Runs the processor over one block, in place. Audio thread.
    private func render(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard isFloat, frameCount > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        #if DEBUG
        measure(buffers, frameCount: frameCount, isInput: true)
        #endif
        processor.beginBlock(frameCount: frameCount)
        var channel = 0
        for buffer in buffers {
            let stride = Int(buffer.mNumberChannels)
            if let data = buffer.mData?.assumingMemoryBound(to: Float.self), stride > 0 {
                processor.process(data, frameCount: frameCount, channelStride: stride, firstChannel: channel)
            }
            channel += stride
        }
        #if DEBUG
        measure(buffers, frameCount: frameCount, isInput: false)
        #endif
    }

    #if DEBUG
    private func measure(_ buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int, isInput: Bool) {
        var sum = 0.0
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let count = frameCount * Int(buffer.mNumberChannels)
            for index in 0..<count {
                sum += Double(data[index] * data[index])
            }
        }
        if isInput {
            debugInput += sum
            debugFrames += frameCount
        } else {
            debugOutput += sum
        }
    }

    struct DebugSnapshot {
        let frames: Int
        let inputDB: Double
        let outputDB: Double
    }

    func takeDebugSnapshot() -> DebugSnapshot {
        let frames = debugFrames
        let input = debugInput, output = debugOutput
        debugFrames = 0
        debugInput = 0
        debugOutput = 0
        let scale = Double(max(1, frames))
        return DebugSnapshot(frames: frames,
                             inputDB: 10 * log10(max(input / scale, 1e-12)),
                             outputDB: 10 * log10(max(output / scale, 1e-12)))
    }
    #endif
}
