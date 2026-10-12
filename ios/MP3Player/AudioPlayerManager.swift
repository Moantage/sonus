import AVFoundation
import MediaPlayer
import SonusCore
import SwiftUI
import UIKit

/// Plays the library. Imported and downloaded songs play from their file; everything else streams
/// from its source. Playback runs on ``QueuePlayerEngine`` (an `AVQueuePlayer`), which preloads the
/// next song so streams start without a gap.
@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
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
            refreshUpcomingItem()
            updateNowPlayingInfo()
        }
    }
    @Published var lastPlaybackError: String?

    // MARK: - Streaming

    /// True while playback waits for the network: a stream starting, a seek loading, or a stall.
    @Published private(set) var isBuffering = false
    /// True when the current song streams from its source instead of playing a file on this device.
    @Published private(set) var isStreaming = false
    /// Seconds of the current song loaded so far, for a buffer bar under the scrubber.
    @Published private(set) var bufferedTime: TimeInterval = 0

    // MARK: - Premium: advanced controls

    /// Playback speed (pitch-preserved). 1.0 = normal.
    @Published private(set) var playbackSpeed: Float = 1.0
    static let availableSpeeds: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// When set, playback auto-pauses at this time.
    @Published private(set) var sleepTimerEndsAt: Date?

    /// Premium high-quality output (higher session sample rate + best route).
    @Published private(set) var highQualityAudioEnabled: Bool

    private let engine = QueuePlayerEngine()
    private let nowPlaying = NowPlayingCenter()
    private let audioSession = AudioSessionController()
    private var currentIndex: Int?
    private var artwork: MPMediaItemArtwork?
    private var sleepTimer: Timer?
    /// What the person asked for, as opposed to what the player is doing (it may be buffering or
    /// interrupted). Decides whether to resume after an interruption.
    private var wantsPlayback = false
    private var resumeAfterInterruption = false

    override init() {
        if let rawID = KeychainManager.shared.retrieve(for: KeychainKeys.lastPlayedSongID) {
            lastPlayedSongID = UUID(uuidString: rawID)
        }
        highQualityAudioEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.highQualityAudio)

        super.init()
        configureAudioSession()
        engine.events = engineEvents()
        audioSession.observe(audioSessionHandlers())
        nowPlaying.register(controlling: self)
    }

    var progress: Double {
        guard duration > 0 else {
            return 0
        }

        return currentTime / duration
    }

    func play(song: Song, in queue: [Song]) {
        activeQueue = queue
        currentIndex = queue.firstIndex { $0.id == song.id }
        load(song: song, shouldAutoPlay: true)
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        wantsPlayback = false
        engine.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resume() {
        guard !engine.hasFailed else {
            // Nothing loaded, or the last attempt failed (e.g. offline): load the song again.
            if let currentSong {
                load(song: currentSong, shouldAutoPlay: true)
            }
            return
        }
        startPlayback()
    }

    func stopPlayback() {
        wantsPlayback = false
        engine.stop()
        currentSong = nil
        activeQueue = []
        currentIndex = nil
        currentTime = 0
        duration = 0
        bufferedTime = 0
        isPlaying = false
        isBuffering = false
        isStreaming = false
        artwork = nil
        artworkImage = nil
        nowPlaying.clear()
        updateRemoteCommandAvailability()
    }

    /// Keeps the queue in step with the library: deleted songs leave it, and refreshed details
    /// (tags read, a download finished) replace the old copies.
    func syncLibrary(with songs: [Song]) {
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let queue = activeQueue.compactMap { byID[$0.id] }
        if queue != activeQueue {
            activeQueue = queue
        }

        if let currentSong {
            guard let fresh = byID[currentSong.id] else {
                stopPlayback()
                return
            }
            currentIndex = activeQueue.firstIndex { $0.id == fresh.id }
            if fresh != currentSong {
                self.currentSong = fresh
                updateNowPlayingInfo()
            }
        }

        if let lastPlayedSongID, byID[lastPlayedSongID] == nil {
            persistLastPlayedSongID(nil)
        }
        refreshUpcomingItem()
    }

    func playNext() {
        guard let currentIndex, currentIndex + 1 < activeQueue.count else {
            return
        }

        let nextIndex = currentIndex + 1
        let next = activeQueue[nextIndex]
        self.currentIndex = nextIndex
        if let upcoming = engine.upcomingItem, upcoming.songID == next.id, upcoming.status != .failed {
            // Already preloaded: keep what it has buffered.
            engine.advanceToUpcoming()
            becomeCurrent(upcoming, song: next)
            startPlayback()
        } else {
            load(song: next, shouldAutoPlay: true)
        }
    }

    func playPrevious() {
        guard activeQueue.isEmpty == false else {
            return
        }

        if currentTime > 3, let currentSong {
            // Restart the current song.
            if engine.hasFailed {
                load(song: currentSong, shouldAutoPlay: true)
            } else {
                seek(to: 0)
                startPlayback()
            }
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
        engine.setRate(speed)
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
        guard engine.currentItem != nil, duration > 0 else {
            return
        }

        let clampedTime = min(max(newTime, 0), duration)
        currentTime = clampedTime
        engine.seek(to: clampedTime, exact: !isStreaming) { [weak self] reached in
            guard let self else { return }
            if let reached {
                self.currentTime = reached
            }
            self.updateNowPlayingInfo()
        }
        updateNowPlayingInfo()
    }
}

// MARK: - Loading and the queue

private extension AudioPlayerManager {
    var nextSong: Song? {
        guard let currentIndex, currentIndex + 1 < activeQueue.count else { return nil }
        return activeQueue[currentIndex + 1]
    }

    func makeItem(for song: Song) throws -> SonusPlayerItem {
        SonusPlayerItem(songID: song.id, prepared: try PlayerAssetFactory.asset(for: song))
    }

    func load(song: Song, shouldAutoPlay: Bool) {
        let item: SonusPlayerItem
        do {
            item = try makeItem(for: song)
        } catch {
            lastPlaybackError = (error as? PlaybackUnavailableError)?.message ?? StreamingErrorMessages.generic
            return
        }

        engine.replace(with: item)
        becomeCurrent(item, song: song)
        lastPlaybackError = nil

        if shouldAutoPlay {
            startPlayback()
        } else {
            wantsPlayback = false
            engine.pause()
            isPlaying = false
            updateNowPlayingInfo()
        }
    }

    func becomeCurrent(_ item: SonusPlayerItem, song: Song) {
        currentSong = song
        isStreaming = !item.isLocal
        duration = song.duration > 0 ? song.duration : 0
        currentTime = 0
        bufferedTime = 0
        artworkImage = ArtworkCache.image(for: song.id)
        artwork = NowPlayingCenter.artwork(from: artworkImage)
        persistLastPlayedSongID(song.id)

        if let queueIndex = activeQueue.firstIndex(where: { $0.id == song.id }) {
            currentIndex = queueIndex
        } else {
            activeQueue = [song]
            currentIndex = 0
        }

        loadTags(of: item, for: song)
        refreshUpcomingItem()
        updateNowPlayingInfo()
    }

    func startPlayback() {
        wantsPlayback = true
        engine.play(rate: playbackSpeed)
        isPlaying = true
        updateNowPlayingInfo()
    }

    /// Preloads the next song so it starts without a gap, or empties the slot when repeat-one is on
    /// or the queue ends here.
    func refreshUpcomingItem() {
        guard engine.currentItem != nil else { return }
        guard repeatMode == .off, let next = nextSong else {
            engine.setUpcoming(nil)
            return
        }
        if let upcoming = engine.upcomingItem, upcoming.songID == next.id,
           upcoming.isLocal == next.isDownloadedLocally, upcoming.status != .failed {
            engine.setUpcoming(upcoming)
        } else {
            engine.setUpcoming(try? makeItem(for: next))
        }
    }

    /// The engine moved to the preloaded song by itself.
    func handleAdvance(to item: SonusPlayerItem) {
        guard item.songID != currentSong?.id, let index = activeQueue.firstIndex(where: { $0.id == item.songID }) else {
            return
        }
        currentIndex = index
        if item.status == .failed {
            // The preload failed (say, the network dropped); try once more from scratch.
            load(song: activeQueue[index], shouldAutoPlay: wantsPlayback)
        } else {
            becomeCurrent(item, song: activeQueue[index])
        }
    }

    func handleFinish() {
        if repeatMode == .one {
            seek(to: 0)
            startPlayback()
            return
        }

        let beforeAdvance = currentSong?.id
        playNext()
        if beforeAdvance == currentSong?.id {
            // End of the queue: stop at the start of the last song, like before.
            wantsPlayback = false
            engine.pause()
            isPlaying = false
            seek(to: 0)
            currentTime = 0
            updateNowPlayingInfo()
        }
    }

    /// Reads the song's own tags for lock-screen artwork; `LibraryStore` takes the title and artist.
    func loadTags(of item: SonusPlayerItem, for song: Song) {
        Task { [weak self] in
            let image = await TrackTags.readForPlayback(item.asset, song: song)
            guard let self, self.currentSong?.id == song.id, let image else { return }
            self.artworkImage = image
            self.artwork = NowPlayingCenter.artwork(from: image)
            self.updateNowPlayingInfo()
        }
    }

    func engineEvents() -> QueuePlayerEngine.Events {
        QueuePlayerEngine.Events(
            tick: { [weak self] time, buffered in
                guard let self else { return }
                if abs(time - self.currentTime) >= 0.01 { self.currentTime = time }
                if abs(buffered - self.bufferedTime) >= 0.5 { self.bufferedTime = buffered }
            },
            durationKnown: { [weak self] seconds in
                self?.duration = seconds
                self?.updateNowPlayingInfo()
            },
            statusChanged: { [weak self] playing, buffering in
                self?.isPlaying = playing
                self?.isBuffering = buffering
                self?.updateNowPlayingInfo()
            },
            advanced: { [weak self] item in self?.handleAdvance(to: item) },
            finished: { [weak self] in self?.handleFinish() },
            failed: { [weak self] error in
                guard let self else { return }
                self.isPlaying = false
                self.isBuffering = false
                self.lastPlaybackError = PlaybackErrorText.message(for: error)
                self.updateNowPlayingInfo()
            }
        )
    }
}

// MARK: - Audio session, lock screen and remote commands

private extension AudioPlayerManager {
    func configureAudioSession() {
        if !audioSession.configure(highQuality: highQualityAudioEnabled) {
            lastPlaybackError = "Audio session setup failed."
        }
    }

    func audioSessionHandlers() -> AudioSessionController.Handlers {
        AudioSessionController.Handlers(
            interruptionBegan: { [weak self] in
                guard let self else { return }
                self.resumeAfterInterruption = self.wantsPlayback
                self.isPlaying = false
                self.updateNowPlayingInfo()
            },
            interruptionEnded: { [weak self] shouldResume in
                guard let self else { return }
                if shouldResume && self.resumeAfterInterruption {
                    self.audioSession.reactivate()
                    self.startPlayback()
                }
                self.resumeAfterInterruption = false
            },
            outputLost: { [weak self] in
                // Headphones unplugged: the player paused itself; don't resume on the speaker later.
                self?.wantsPlayback = false
            },
            mediaServicesReset: { [weak self] in
                guard let self else { return }
                self.configureAudioSession()
                if let song = self.currentSong {
                    self.load(song: song, shouldAutoPlay: false)
                }
            }
        )
    }

    func updateRemoteCommandAvailability() {
        nowPlaying.updateAvailability(queueCount: activeQueue.count, hasDuration: duration > 0)
    }

    func updateNowPlayingInfo() {
        updateRemoteCommandAvailability()
        guard let currentSong else {
            nowPlaying.clear()
            return
        }
        let elapsed = engine.isSeeking ? currentTime : (engine.currentSeconds ?? currentTime)
        nowPlaying.show(NowPlayingCenter.Snapshot(
            title: currentSong.title,
            artist: currentSong.displayArtist,
            album: currentSong.albumName,
            elapsed: elapsed,
            duration: duration,
            // 0 while paused or buffering, so the lock-screen clock doesn't run ahead.
            rate: engine.isActuallyPlaying ? Double(playbackSpeed) : 0,
            defaultRate: Double(playbackSpeed),
            artwork: artwork
        ))
    }

    func persistLastPlayedSongID(_ songID: Song.ID?) {
        guard lastPlayedSongID != songID || songID == nil else { return }
        lastPlayedSongID = songID

        if let songID {
            _ = KeychainManager.shared.store(songID.uuidString, for: KeychainKeys.lastPlayedSongID)
        } else {
            _ = KeychainManager.shared.delete(for: KeychainKeys.lastPlayedSongID)
        }
    }
}
