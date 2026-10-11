import MediaPlayer
import UIKit

/// The lock screen, Control Center and headphone controls: Now Playing info plus remote commands.
@MainActor
final class NowPlayingCenter {
    /// What the remote commands do. Each runs on the main thread.
    struct Commands {
        var play: () -> Void
        var pause: () -> Void
        var togglePlayPause: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var seek: (TimeInterval) -> Void
    }

    /// The state shown on the lock screen.
    struct Snapshot {
        var title: String
        var artist: String
        var album: String?
        var elapsed: TimeInterval
        var duration: TimeInterval
        /// 0 while paused or buffering, so the lock-screen clock doesn't run ahead.
        var rate: Double
        var defaultRate: Double
        var artwork: MPMediaItemArtwork?
    }

    func register(_ commands: Commands) {
        let center = MPRemoteCommandCenter.shared()
        // Next and previous are disabled (see updateAvailability) when there's nowhere to go, and
        // the player ignores them at the ends of the queue anyway.
        let simple: [(MPRemoteCommand, () -> Void)] = [
            (center.playCommand, commands.play),
            (center.pauseCommand, commands.pause),
            (center.togglePlayPauseCommand, commands.togglePlayPause),
            (center.nextTrackCommand, commands.next),
            (center.previousTrackCommand, commands.previous)
        ]
        for (command, action) in simple {
            command.removeTarget(nil)
            command.addTarget { _ in
                DispatchQueue.main.async { action() }
                return .success
            }
        }

        center.changePlaybackPositionCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = positionEvent.positionTime
            DispatchQueue.main.async { commands.seek(position) }
            return .success
        }
        updateAvailability(queueCount: 0, hasDuration: false)
    }

    func updateAvailability(queueCount: Int, hasDuration: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = queueCount > 1
        center.previousTrackCommand.isEnabled = queueCount > 0
        center.changePlaybackPositionCommand.isEnabled = hasDuration
    }

    func show(_ snapshot: Snapshot) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.artist,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: snapshot.defaultRate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let album = snapshot.album, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let artwork = snapshot.artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Lock-screen artwork: the song's own, or the app's placeholder.
    static func artwork(from image: UIImage?) -> MPMediaItemArtwork? {
        guard let image = image ?? UIImage(named: "PlayerArtwork") else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
