import AVFoundation
import SonusCore
import UIKit

/// A song's own tags (ID3 or MP4 metadata), read from its file or, for streams, from the first
/// bytes through the same loader playback uses.
struct TrackTags {
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    var artworkData: Data?

    static func read(from asset: AVAsset) async -> TrackTags {
        var tags = TrackTags()
        if let metadata = try? await asset.load(.commonMetadata) {
            tags.title = await string(for: .commonIdentifierTitle, in: metadata)
            tags.artist = await string(for: .commonIdentifierArtist, in: metadata)
            tags.album = await string(for: .commonIdentifierAlbumName, in: metadata)
            if let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first {
                tags.artworkData = try? await item.load(.dataValue)
            }
        }
        if let time = try? await asset.load(.duration), time.seconds.isFinite, time.seconds > 0 {
            tags.duration = time.seconds
        }
        return tags
    }

    /// Reads a playing song's tags, caches its artwork (from the tags, else the source's cover
    /// URL) and announces the tags so `LibraryStore` can replace a guessed title. Returns the artwork.
    @MainActor
    static func readForPlayback(_ asset: AVAsset, song: Song) async -> UIImage? {
        let sources = SourceStore.shared
        let client = sources.httpClient
        let authorization = sources.source(id: song.sourceID).flatMap(sources.authorization(for:))
        let tags = await read(from: asset)
        var image = tags.artworkData.flatMap { ArtworkCache.save($0, for: song.id) }
        if image == nil, ArtworkCache.image(for: song.id) == nil, let url = song.remoteArtworkURL {
            image = await ArtworkCache.download(url, for: song.id, client: client, authorization: authorization)
        }
        NotificationCenter.default.post(name: .sonusTrackTagsRead, object: TrackTagsReading(songID: song.id, tags: tags))
        return image
    }

    private static func string(for identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first,
              let value = try? await item.load(.stringValue) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Tags read for a song, posted with ``Foundation/Notification/Name/sonusTrackTagsRead``.
struct TrackTagsReading {
    let songID: Song.ID
    let tags: TrackTags
}

extension Notification.Name {
    /// Posted on the main thread when a song's own tags were read. The object is a
    /// ``TrackTagsReading``; `LibraryStore` replaces file-name titles with the tags.
    static let sonusTrackTagsRead = Notification.Name("SonusTrackTagsRead")
    /// Posted on the main thread when a download finished. The object is the song's ID.
    static let sonusDownloadCompleted = Notification.Name("SonusDownloadCompleted")
}

/// Cover art found in songs' tags, saved small so lists can show it without the network.
enum ArtworkCache {
    static let maxPixelSize: CGFloat = 600

    /// Saves a downscaled JPEG of `data` for the song and returns the image, or nil if `data`
    /// isn't an image.
    @discardableResult
    static func save(_ data: Data, for songID: UUID) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxPixelSize ? maxPixelSize / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumbnail = image.preparingThumbnail(of: size) ?? image
        if let jpeg = thumbnail.jpegData(compressionQuality: 0.85) {
            try? jpeg.write(to: AppPaths.artworkFileURL(for: songID), options: .atomic)
        }
        return thumbnail
    }

    /// Downloads a source's cover art for the song and caches it.
    static func download(
        _ url: URL,
        for songID: UUID,
        client: StreamingHTTPClient,
        authorization: RequestAuthorization?
    ) async -> UIImage? {
        guard let data = try? await client.data(url, authorization: authorization, maxBytes: 8 * 1024 * 1024).data else {
            return nil
        }
        return save(data, for: songID)
    }

    static func image(for songID: UUID) -> UIImage? {
        UIImage(contentsOfFile: AppPaths.artworkFileURL(for: songID).path)
    }

    static func remove(for songID: UUID) {
        try? FileManager.default.removeItem(at: AppPaths.artworkFileURL(for: songID))
    }
}

/// Reads tags for songs whose titles are still guesses from file names (repository listings),
/// a couple at a time, right after a refresh. Songs it doesn't reach get their tags when played.
@MainActor
final class TrackTagEnricher {
    static let shared = TrackTagEnricher()

    private static let maxPerRefresh = 200
    private static let maxConcurrent = 2

    private weak var library: LibraryStore?
    private var pending: [Song.ID] = []
    private var queued = Set<Song.ID>()
    private var running = 0

    func enqueue(_ songs: [Song], library: LibraryStore) {
        self.library = library
        for song in songs.prefix(Self.maxPerRefresh) where song.hasProvisionalMetadata == true {
            if queued.insert(song.id).inserted {
                pending.append(song.id)
            }
        }
        pump()
    }

    private func pump() {
        while running < Self.maxConcurrent, !pending.isEmpty {
            let songID = pending.removeFirst()
            guard let song = library?.songs.first(where: { $0.id == songID }), song.hasProvisionalMetadata == true,
                  let prepared = try? PlayerAssetFactory.asset(for: song) else {
                queued.remove(songID)
                continue
            }
            running += 1
            Task {
                let tags = await TrackTags.read(from: prepared.asset)
                withExtendedLifetime(prepared.loader) {}
                finish(songID, tags: tags)
            }
        }
    }

    private func finish(_ songID: Song.ID, tags: TrackTags) {
        running -= 1
        queued.remove(songID)
        if let artworkData = tags.artworkData {
            ArtworkCache.save(artworkData, for: songID)
        }
        library?.applyReadTags(tags, to: songID)
        pump()
    }
}
