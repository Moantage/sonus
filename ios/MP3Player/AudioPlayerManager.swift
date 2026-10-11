import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private enum KeychainKeys {
        static let lastPlayedSongID = "lastPlayedSongID"
    }
    private enum DefaultsKeys {
        static let highQualityAudio = "premium.highQualityAudio"
    }

    @Published private(set) var currentSong: Song?
    @Published private(set) var activeQueue: [Song] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastPlayedSongID: Song.ID?
    @Published private(set) var artworkImage: UIImage?
    @Published var repeatMode: RepeatMode = .off {
        didSet {
            updateNowPlayingInfo()
        }
    }
    @Published var lastPlaybackError: String?

    // MARK: - Premium: advanced controls

    /// Playback speed (pitch-preserved). 1.0 = normal.
    @Published private(set) var playbackSpeed: Float = 1.0
    static let availableSpeeds: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// When set, playback auto-pauses at this time.
    @Published private(set) var sleepTimerEndsAt: Date?

    /// Premium high-quality output (higher session sample rate + best route).
    @Published private(set) var highQualityAudioEnabled: Bool

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private var currentIndex: Int?
    private var artwork: MPMediaItemArtwork?
    private var sleepTimer: Timer?

    override init() {
        if let rawID = KeychainManager.shared.retrieve(for: KeychainKeys.lastPlayedSongID) {
            lastPlayedSongID = UUID(uuidString: rawID)
        }
        highQualityAudioEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.highQualityAudio)

        super.init()
        configureAudioSession()
        configureRemoteCommands()
        startProgressTimer()
    }

    deinit {
        progressTimer?.invalidate()
        sleepTimer?.invalidate()
    }

    var progress: Double {
        guard duration > 0 else {
            return 0
        }

        return currentTime / duration
    }

    func play(song: Song, in queue: [Song]) {
        activeQueue = queue

        guard let index = queue.firstIndex(of: song) else {
            load(song: song, shouldAutoPlay: true)
            return
        }

        currentIndex = index
        load(song: song, shouldAutoPlay: true)
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resume() {
        guard let audioPlayer else {
            if let currentSong {
                load(song: currentSong, shouldAutoPlay: true)
            }
            return
        }

        audioPlayer.play()
        audioPlayer.enableRate = true
        audioPlayer.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentSong = nil
        activeQueue = []
        currentIndex = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        artwork = nil
        artworkImage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateRemoteCommandAvailability()
    }

    func syncLibrary(with songs: [Song]) {
        let validSongIDs = Set(songs.map(\.id))

        activeQueue.removeAll { validSongIDs.contains($0.id) == false }

        if let currentSong, validSongIDs.contains(currentSong.id) == false {
            stopPlayback()
        } else if let currentSong, let index = activeQueue.firstIndex(of: currentSong) {
            currentIndex = index
        }

        if let lastPlayedSongID, validSongIDs.contains(lastPlayedSongID) == false {
            persistLastPlayedSongID(nil)
        }
    }

    func playNext() {
        guard activeQueue.isEmpty == false else {
            return
        }

        if let currentIndex, currentIndex + 1 < activeQueue.count {
            let nextIndex = currentIndex + 1
            self.currentIndex = nextIndex
            load(song: activeQueue[nextIndex], shouldAutoPlay: true)
            return
        }
    }

    func playPrevious() {
        guard activeQueue.isEmpty == false else {
            return
        }

        if currentTime > 3, let currentSong {
            load(song: currentSong, shouldAutoPlay: true)
            return
        }

        if let currentIndex, currentIndex > 0 {
            let previousIndex = currentIndex - 1
            self.currentIndex = previousIndex
            load(song: activeQueue[previousIndex], shouldAutoPlay: true)
        }
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode == .one ? .off : .one
    }

    // MARK: - Premium: advanced controls

    /// Sets pitch-preserved playback speed and applies it immediately.
    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        audioPlayer?.enableRate = true
        if isPlaying { audioPlayer?.rate = speed }   // takes effect now; else applied on next play
        updateNowPlayingInfo()
    }

    func skipForward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }

    func skipBackward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    /// Starts a sleep timer; playback pauses after `minutes`.
    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else { return }
        let interval = TimeInterval(minutes * 60)
        sleepTimerEndsAt = Date().addingTimeInterval(interval)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pause()
                self?.cancelSleepTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndsAt = nil
    }

    /// Enables/disables premium high-quality audio output and reconfigures the session.
    func setHighQualityAudio(_ enabled: Bool) {
        highQualityAudioEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKeys.highQualityAudio)
        configureAudioSession()
    }

    func seek(to newTime: TimeInterval) {
        guard let audioPlayer, duration > 0 else {
            return
        }

        let clampedTime = min(max(newTime, 0), duration)
        audioPlayer.currentTime = clampedTime
        currentTime = clampedTime
        updateNowPlayingInfo()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            if self.repeatMode == .one, let currentSong = self.currentSong {
                self.load(song: currentSong, shouldAutoPlay: true)
                return
            }

            let beforeAdvance = self.currentSong
            self.playNext()

            if beforeAdvance == self.currentSong {
                self.isPlaying = false
                self.currentTime = 0
                self.updateNowPlayingInfo()
            }
        }
    }

    private func load(song: Song, shouldAutoPlay: Bool) {
        do {
            let url = AppPaths.fileURL(for: song)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()

            audioPlayer = player
            currentSong = song
            duration = player.duration
            currentTime = 0
            artworkImage = extractArtworkImage(for: url)
            artwork = makeArtwork(from: artworkImage)
            persistLastPlayedSongID(song.id)

            if let queueIndex = activeQueue.firstIndex(of: song) {
                currentIndex = queueIndex
            } else {
                activeQueue = [song]
                currentIndex = 0
            }

            // Preserve the chosen playback speed across track changes.
            player.enableRate = true

            if shouldAutoPlay {
                player.play()
                player.rate = playbackSpeed
                isPlaying = true
            } else {
                isPlaying = false
            }

            updateRemoteCommandAvailability()
            updateNowPlayingInfo()
            lastPlaybackError = nil
        } catch {
            lastPlaybackError = "This track could not be played."
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            // High quality: long-form audio mode routes to the best available
            // output and enables high-quality Bluetooth (A2DP) + AirPlay.
            let options: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP]
            let mode: AVAudioSession.Mode = highQualityAudioEnabled ? .default : .default
            try session.setCategory(.playback, mode: mode, options: options)

            if highQualityAudioEnabled {
                // Prefer a high sample rate so we never downsample premium output.
                try? session.setPreferredSampleRate(48_000)
                try? session.setPreferredIOBufferDuration(0.005)
            } else {
                try? session.setPreferredSampleRate(44_100)
            }

            try session.setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {
            lastPlaybackError = "Audio session setup failed."
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }

            DispatchQueue.main.async {
                self.resume()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }

            DispatchQueue.main.async {
                self.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }

            DispatchQueue.main.async {
                self.togglePlayback()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.activeQueue.count > 1 else {
                return .commandFailed
            }

            DispatchQueue.main.async {
                self.playNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.activeQueue.isEmpty == false else {
                return .commandFailed
            }

            DispatchQueue.main.async {
                self.playPrevious()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard
                let self,
                let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else {
                return .commandFailed
            }

            DispatchQueue.main.async {
                self.seek(to: positionEvent.positionTime)
            }
            return .success
        }

        updateRemoteCommandAvailability()
    }

    private func updateRemoteCommandAvailability() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = activeQueue.count > 1
        commandCenter.previousTrackCommand.isEnabled = activeQueue.isEmpty == false
        commandCenter.changePlaybackPositionCommand.isEnabled = duration > 0
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.syncPlaybackState()
        }
        RunLoop.main.add(progressTimer!, forMode: .common)
    }

    private func syncPlaybackState() {
        guard let audioPlayer else {
            return
        }

        currentTime = audioPlayer.currentTime
        duration = audioPlayer.duration
        isPlaying = audioPlayer.isPlaying

        if currentSong != nil {
            updateNowPlayingInfo()
        }
    }

    private func updateNowPlayingInfo() {
        guard let currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentSong.title,
            MPMediaItemPropertyArtist: currentSong.displayArtist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0
        ]

        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateRemoteCommandAvailability()
    }

    private func extractArtworkImage(for fileURL: URL) -> UIImage? {
        let asset = AVURLAsset(url: fileURL)
        let items = AVMetadataItem.metadataItems(from: asset.commonMetadata, filteredByIdentifier: .commonIdentifierArtwork)

        guard
            let data = items.first?.dataValue,
            let image = UIImage(data: data)
        else {
            return nil
        }

        return image
    }

    private func makeArtwork(from image: UIImage?) -> MPMediaItemArtwork? {
        if let image {
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        guard let fallbackImage = UIImage(named: "PlayerArtwork") else {
            return nil
        }

        return MPMediaItemArtwork(boundsSize: fallbackImage.size) { _ in fallbackImage }
    }

    private func persistLastPlayedSongID(_ songID: Song.ID?) {
        lastPlayedSongID = songID

        if let songID {
            _ = KeychainManager.shared.store(songID.uuidString, for: KeychainKeys.lastPlayedSongID)
        } else {
            _ = KeychainManager.shared.delete(for: KeychainKeys.lastPlayedSongID)
        }
    }
}
