import AVFoundation
import UIKit

/// The app's audio session: the playback category, the Premium quality preference, and the system
/// events the player reacts to (interruptions, unplugged headphones, media-services resets).
@MainActor
final class AudioSessionController {
    struct Handlers {
        var interruptionBegan: @MainActor () -> Void
        /// `shouldResume` is the system's hint that playback may continue.
        var interruptionEnded: @MainActor (_ shouldResume: Bool) -> Void
        /// The output went away (headphones unplugged); the player has already paused itself.
        var outputLost: @MainActor () -> Void
        var mediaServicesReset: @MainActor () -> Void
    }

    private var tokens: [NSObjectProtocol] = []

    /// Sets up playback. Returns false when the session couldn't be configured.
    @discardableResult
    func configure(highQuality: Bool) -> Bool {
        let session = AVAudioSession.sharedInstance()

        do {
            // High quality: long-form audio mode routes to the best available
            // output and enables high-quality Bluetooth (A2DP) + AirPlay.
            let options: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP]
            try session.setCategory(.playback, mode: .default, options: options)

            if highQuality {
                // Prefer a high sample rate so we never downsample premium output.
                try? session.setPreferredSampleRate(48_000)
                try? session.setPreferredIOBufferDuration(0.005)
            } else {
                try? session.setPreferredSampleRate(44_100)
            }

            try session.setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
            return true
        } catch {
            return false
        }
    }

    func reactivate() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func observe(_ handlers: Handlers) {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        tokens = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
                let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                MainActor.assumeIsolated {
                    switch rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
                    case .began:
                        handlers.interruptionBegan()
                    case .ended:
                        handlers.interruptionEnded(shouldResume)
                    default:
                        break
                    }
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
                let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                guard rawReason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                MainActor.assumeIsolated { handlers.outputLost() }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
                MainActor.assumeIsolated { handlers.mediaServicesReset() }
            }
        ]
    }
}
