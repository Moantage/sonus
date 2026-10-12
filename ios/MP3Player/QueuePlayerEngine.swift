import AVFoundation

/// The `AVQueuePlayer` under `AudioPlayerManager`: the current song plus at most one preloaded
/// next song, with all of AVFoundation's observation turned into a few main-thread events.
@MainActor
final class QueuePlayerEngine {
    struct Events {
        /// Every half second while there's an item: position and how far it has loaded.
        var tick: @MainActor (_ time: TimeInterval, _ buffered: TimeInterval) -> Void
        /// The current item's real duration became known.
        var durationKnown: @MainActor (TimeInterval) -> Void
        /// Playing, waiting for data (buffering), or paused.
        var statusChanged: @MainActor (_ isPlaying: Bool, _ isBuffering: Bool) -> Void
        /// The player moved on to the preloaded item by itself.
        var advanced: @MainActor (SonusPlayerItem) -> Void
        /// The current item reached its end with nothing preloaded after it.
        var finished: @MainActor () -> Void
        /// The current item failed to load or play.
        var failed: @MainActor (_ error: (any Error)?) -> Void
    }

    var events: Events?

    private let player = AVQueuePlayer()
    private var timeObserver: Any?
    private var playerObservations: [NSKeyValueObservation] = []
    private var itemObservation: NSKeyValueObservation?
    private weak var watchedItem: SonusPlayerItem?
    private var notificationTokens: [NSObjectProtocol] = []
    private var seekGeneration = 0
    private(set) var isSeeking = false
    private var reportedDuration: TimeInterval = 0

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
        observePlayer()
    }

    var currentItem: SonusPlayerItem? {
        player.currentItem as? SonusPlayerItem
    }

    var upcomingItem: SonusPlayerItem? {
        player.items().dropFirst().first as? SonusPlayerItem
    }

    var hasFailed: Bool {
        player.currentItem == nil || player.currentItem?.status == .failed
    }

    var isActuallyPlaying: Bool {
        player.timeControlStatus == .playing
    }

    var currentSeconds: TimeInterval? {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : nil
    }

    /// Replaces everything with `item`.
    func replace(with item: SonusPlayerItem) {
        player.removeAllItems()
        player.insert(item, after: nil)
        watch(item)
    }

    /// Puts `item` in the preload slot (or empties it). With something preloaded the player moves
    /// on by itself at the end of the current song; otherwise it pauses there.
    func setUpcoming(_ item: SonusPlayerItem?) {
        guard let current = player.currentItem else { return }
        if let item, item === upcomingItem {
            player.actionAtItemEnd = .advance
            return
        }
        for queued in player.items() where queued !== current {
            player.remove(queued)
        }
        guard let item, player.canInsert(item, after: current) else {
            player.actionAtItemEnd = .pause
            return
        }
        player.insert(item, after: current)
        player.actionAtItemEnd = .advance
    }

    /// Moves to the preloaded item now, keeping what it has buffered.
    func advanceToUpcoming() {
        guard let upcoming = upcomingItem else { return }
        player.advanceToNextItem()
        watch(upcoming)
    }

    func play(rate: Float) {
        player.defaultRate = rate
        player.play()
    }

    func pause() {
        player.pause()
    }

    func setRate(_ rate: Float) {
        player.defaultRate = rate
        if player.rate != 0 {
            player.rate = rate
        }
    }

    func stop() {
        player.removeAllItems()
        itemObservation = nil
        watchedItem = nil
    }

    /// Seeks, exactly for local files and with a little slack for streams so less has to load.
    /// `completion` gets the position reached, unless a later seek replaced this one.
    func seek(to seconds: TimeInterval, exact: Bool, completion: @escaping @MainActor (TimeInterval?) -> Void) {
        isSeeking = true
        seekGeneration += 1
        let generation = seekGeneration
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 0.5, preferredTimescale: 600)
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, generation == self.seekGeneration else { return }
                self.isSeeking = false
                completion(self.currentSeconds)
            }
        }
    }

    // MARK: - Observation

    private func observePlayer() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        playerObservations = [
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.reportStatus() }
            },
            player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.currentItemChanged() }
            }
        ]
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                let item = note.object as? AVPlayerItem
                MainActor.assumeIsolated { self?.itemDidFinish(item) }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                let item = note.object as? AVPlayerItem
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                MainActor.assumeIsolated { self?.itemDidFail(item, error: error) }
            }
        ]
    }

    private func watch(_ item: SonusPlayerItem) {
        watchedItem = item
        reportedDuration = 0
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, item === self.player.currentItem else { return }
                if item.status == .failed {
                    self.events?.failed(item.error)
                } else if item.status == .readyToPlay {
                    self.reportDuration(of: item)
                }
            }
        }
    }

    private func tick(_ time: CMTime) {
        guard !isSeeking, let item = player.currentItem else { return }
        reportDuration(of: item)
        let loaded = item.loadedTimeRanges.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds }.max() ?? 0
        let seconds = time.seconds
        events?.tick(seconds.isFinite ? seconds : 0, loaded.isFinite ? loaded : 0)
    }

    private func reportDuration(of item: AVPlayerItem) {
        let seconds = item.duration.seconds
        guard seconds.isFinite, seconds > 0, abs(seconds - reportedDuration) > 0.5 else { return }
        reportedDuration = seconds
        events?.durationKnown(seconds)
    }

    private func reportStatus() {
        switch player.timeControlStatus {
        case .playing:
            events?.statusChanged(true, false)
        case .waitingToPlayAtSpecifiedRate:
            events?.statusChanged(true, player.reasonForWaitingToPlay != .noItemToPlay)
        case .paused:
            events?.statusChanged(false, false)
        @unknown default:
            break
        }
    }

    private func currentItemChanged() {
        guard let item = currentItem, item !== watchedItem else { return }
        watch(item)
        events?.advanced(item)
    }

    private func itemDidFinish(_ item: AVPlayerItem?) {
        // With something preloaded, the player moves on by itself (or already has).
        guard let item, item === player.currentItem, player.items().count == 1 else { return }
        events?.finished()
    }

    private func itemDidFail(_ item: AVPlayerItem?, error: (any Error)?) {
        guard let item else { return }
        if item === player.currentItem {
            events?.failed(error)
        } else if player.items().contains(item) {
            // A preload failed: drop it so the current song ends normally and the next one loads fresh.
            player.remove(item)
            player.actionAtItemEnd = .pause
        }
    }
}

/// A queue entry that remembers its song and keeps its stream loader alive.
final class SonusPlayerItem: AVPlayerItem {
    let songID: Song.ID
    let isLocal: Bool
    /// The asset holds its resource loader weakly; the item keeps it for the asset's lifetime.
    private let loader: AuthorizedResourceLoader?

    init(songID: Song.ID, prepared: PreparedAsset) {
        self.songID = songID
        isLocal = prepared.isLocal
        loader = prepared.loader
        // The designated initializer; the typed-key variant is a convenience initializer that a
        // subclass can't call.
        super.init(asset: prepared.asset, automaticallyLoadedAssetKeys: ["duration"])
        audioTimePitchAlgorithm = .spectral // pitch-preserved speed changes, tuned for music
    }
}
