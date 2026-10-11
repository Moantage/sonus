import Foundation

/// A song already in the library that came from the source being refreshed.
public struct ExistingSourceSong<LocalID: Hashable & Sendable>: Equatable, Sendable {
    public var localID: LocalID
    public var remoteID: String
    public var isDownloaded: Bool

    public init(localID: LocalID, remoteID: String, isDownloaded: Bool) {
        self.localID = localID
        self.remoteID = remoteID
        self.isDownloaded = isDownloaded
    }
}

/// How a refresh changes the library, matched by the source's stable track IDs so refreshing
/// never duplicates songs.
public struct SourceMergePlan<LocalID: Hashable & Sendable>: Equatable, Sendable {
    public struct Update: Equatable, Sendable {
        public var localID: LocalID
        public var track: RemoteTrack
    }

    /// Songs already in the library, with the source's current description.
    public var updates: [Update] = []
    /// Tracks new to the library, in source order.
    public var inserts: [RemoteTrack] = []
    /// Songs the source no longer lists and that aren't downloaded.
    public var removals: [LocalID] = []
    /// Songs the source no longer lists but that stay because they're downloaded.
    public var keptOffline: [LocalID] = []
}

public enum SourceMergePlanner {
    /// Plans a refresh.
    ///
    /// - Tracks are matched by ``RemoteTrack/remoteID``. String comparison is Unicode-canonical,
    ///   so a path in NFC and NFD form is the same track.
    /// - A repeated remote ID counts once (first wins). Extra library songs with the same remote
    ///   ID are removed unless downloaded.
    /// - A song the source dropped is removed, unless it's downloaded: then it stays playable
    ///   offline until the person deletes it.
    public static func plan<LocalID>(
        existing: [ExistingSourceSong<LocalID>],
        incoming: [RemoteTrack]
    ) -> SourceMergePlan<LocalID> {
        var plan = SourceMergePlan<LocalID>()
        var byRemoteID: [String: ExistingSourceSong<LocalID>] = [:]
        for song in existing {
            if byRemoteID[song.remoteID] == nil {
                byRemoteID[song.remoteID] = song
            } else {
                retire(song, in: &plan)
            }
        }

        var seen = Set<String>()
        for track in incoming where seen.insert(track.remoteID).inserted {
            if let match = byRemoteID.removeValue(forKey: track.remoteID) {
                plan.updates.append(.init(localID: match.localID, track: track))
            } else {
                plan.inserts.append(track)
            }
        }

        // Whatever is left in the map is gone from the source. Keep a stable order for callers.
        let leftovers = existing.filter { song in byRemoteID[song.remoteID]?.localID == song.localID }
        for song in leftovers {
            retire(song, in: &plan)
        }
        return plan
    }

    private static func retire<LocalID>(_ song: ExistingSourceSong<LocalID>, in plan: inout SourceMergePlan<LocalID>) {
        if song.isDownloaded {
            plan.keptOffline.append(song.localID)
        } else {
            plan.removals.append(song.localID)
        }
    }
}

/// Counts from applying a ``SourceMergePlan``.
public struct SourceMergeSummary: Equatable, Sendable {
    public var added: Int
    public var updated: Int
    public var removed: Int
    public var keptOffline: Int

    public init(added: Int = 0, updated: Int = 0, removed: Int = 0, keptOffline: Int = 0) {
        self.added = added
        self.updated = updated
        self.removed = removed
        self.keptOffline = keptOffline
    }
}
