import MediaPlayer
import UIKit

/// The lock screen, Control Center and headphone controls: Now Playing info plus remote commands.
@MainActor
final class NowPlayingCenter {
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

    /// Routes the lock screen, Control Center and headphone buttons to `player`. Next and previous
    /// are disabled (see ``updateAvailability(queueCount:hasDuration:)``) when there's nowhere to go.
    func register(controlling player: AudioPlayerManager) {
        let center = MPRemoteCommandCenter.shared()
        let simple: [(MPRemoteCommand, @MainActor (AudioPlayerManager) -> Void)] = [
            (center.playCommand, { $0.resume() }),
            (center.pauseCommand, { $0.pause() }),
            (center.togglePlayPauseCommand, { $0.togglePlayback() }),
            (center.nextTrackCommand, { $0.playNext() }),
            (center.previousTrackCommand, { $0.playPrevious() })
        ]
        for (command, action) in simple {
            command.removeTarget(nil)
            command.addTarget { [weak player] _ in
                DispatchQueue.main.async {
                    if let player { action(player) }
                }
                return .success
            }
        }

        center.changePlaybackPositionCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = positionEvent.positionTime
            DispatchQueue.main.async { player?.seek(to: position) }
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
