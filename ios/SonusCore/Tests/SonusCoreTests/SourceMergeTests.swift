import Foundation
import Testing
@testable import SonusCore

@Suite("Refreshing a source")
struct SourceMergeTests {
    static let baseURL = URL(string: "https://music.example.com/")!

    static func track(_ id: String, title: String? = nil) -> RemoteTrack {
        RemoteTrack(remoteID: id, title: title ?? id, url: baseURL.appendingPathComponent(id))
    }

    @Test("Known tracks update in place, new ones are added, nothing is duplicated")
    func updatesByStableID() {
        let existing = [
            ExistingSourceSong(localID: 1, remoteID: "a", isDownloaded: false),
            ExistingSourceSong(localID: 2, remoteID: "b", isDownloaded: true)
        ]
        let plan = SourceMergePlanner.plan(existing: existing, incoming: [Self.track("b", title: "B2"), Self.track("a"), Self.track("c")])
        #expect(plan.updates.map(\.localID) == [2, 1])
        #expect(plan.updates.first?.track.title == "B2")
        #expect(plan.inserts.map(\.remoteID) == ["c"])
        #expect(plan.removals.isEmpty)
        #expect(plan.keptOffline.isEmpty)
    }

    @Test("Refreshing twice with the same listing changes nothing")
    func idempotent() {
        let incoming = [Self.track("a"), Self.track("b")]
        let first = SourceMergePlanner.plan(existing: [ExistingSourceSong<Int>](), incoming: incoming)
        #expect(first.inserts.count == 2)
        let existing = first.inserts.enumerated().map {
            ExistingSourceSong(localID: $0.offset, remoteID: $0.element.remoteID, isDownloaded: false)
        }
        let second = SourceMergePlanner.plan(existing: existing, incoming: incoming)
        #expect(second.inserts.isEmpty)
        #expect(second.updates.count == 2)
        #expect(second.removals.isEmpty)
    }

    @Test("Dropped tracks go, unless they're downloaded")
    func droppedTracks() {
        let existing = [
            ExistingSourceSong(localID: 1, remoteID: "gone", isDownloaded: false),
            ExistingSourceSong(localID: 2, remoteID: "offline", isDownloaded: true)
        ]
        let plan = SourceMergePlanner.plan(existing: existing, incoming: [])
        #expect(plan.removals == [1])
        #expect(plan.keptOffline == [2])
    }

    @Test("Duplicate IDs collapse to one song")
    func duplicates() {
        let existing = [
            ExistingSourceSong(localID: 1, remoteID: "a", isDownloaded: false),
            ExistingSourceSong(localID: 2, remoteID: "a", isDownloaded: false)
        ]
        let plan = SourceMergePlanner.plan(existing: existing, incoming: [Self.track("a"), Self.track("a", title: "again")])
        #expect(plan.updates.map(\.localID) == [1])
        #expect(plan.updates.first?.track.title == "a")
        #expect(plan.removals == [2])
    }

    @Test("A non-ASCII path is the same track in NFC and NFD form")
    func unicodePaths() {
        let composed = "Mus\u{00E9}e/\u{0915}\u{093F}.mp3"
        let decomposed = "Muse\u{0301}e/\u{0915}\u{093F}.mp3"
        let plan = SourceMergePlanner.plan(
            existing: [ExistingSourceSong(localID: 1, remoteID: composed, isDownloaded: false)],
            incoming: [Self.track(decomposed)]
        )
        #expect(plan.updates.map(\.localID) == [1])
        #expect(plan.inserts.isEmpty)
    }
}

@Suite("Track details")
struct TrackDetailsTests {
    static let url = URL(string: "https://music.example.com/a.mp3")!

    @Test("A file-name guess never overwrites tags that were already read")
    func keepsReadTags() {
        let current = TrackDetails(title: "Real Title", artist: "Artist", album: "Album", duration: 200, isProvisional: false)
        let guess = RemoteTrack(remoteID: "a", title: "a guess", url: Self.url, hasProvisionalMetadata: true)
        #expect(current.refreshed(with: guess) == current)
    }

    @Test("A manifest's own details replace older ones; an unknown duration keeps the known one")
    func manifestWins() {
        let current = TrackDetails(title: "Old", artist: nil, album: nil, duration: 200, isProvisional: false)
        let manifest = RemoteTrack(remoteID: "a", title: "New", url: Self.url, artist: "Artist")
        let refreshed = current.refreshed(with: manifest)
        #expect(refreshed.title == "New")
        #expect(refreshed.artist == "Artist")
        #expect(refreshed.duration == 200)
    }

    @Test("Reading tags replaces a provisional title once, ignoring empty tags")
    func applyingTags() {
        let guess = TrackDetails(title: "a guess", artist: nil, album: nil, duration: 0, isProvisional: true)
        let tagged = guess.applyingTags(title: "  Real  ", artist: "", album: "Album", duration: 180)
        #expect(tagged == TrackDetails(title: "Real", artist: nil, album: "Album", duration: 180, isProvisional: false))
        let again = tagged.applyingTags(title: "Other", artist: "X", album: nil, duration: 10)
        #expect(again == tagged)
    }
}

@Suite("Manifest to tracks")
struct ManifestMappingTests {
    @Test("Tracks resolve their URLs and fall back to album and artist entries")
    func mapsTracks() throws {
        let json = """
        {"sonus": "1.0", "library": {"id": "lib", "name": "Lib"},
         "artists": [{"id": "ar", "name": "The Band"}],
         "albums": [{"id": "al", "title": "First", "artistId": "ar", "artwork": "covers/first.jpg"}],
         "tracks": [
           {"id": "t1", "title": "One", "url": "music/One%20Song.mp3", "albumId": "al", "duration": 61.5,
            "mimeType": "audio/mpeg", "size": 1000, "sha256": "ABCDEF"},
           {"id": "t2", "title": "Two", "url": "https://cdn.example.com/two.m4a", "artist": "Guest"}
         ]}
        """
        let manifestURL = try #require(URL(string: "https://music.example.com/lib/sonus.json"))
        let library = try ManifestLoader.library(from: Data(json.utf8), manifestURL: manifestURL)
        #expect(library.name == "Lib")
        let first = try #require(library.tracks.first)
        #expect(first.remoteID == "t1")
        #expect(first.url.absoluteString == "https://music.example.com/lib/music/One%20Song.mp3")
        #expect(first.artist == "The Band")
        #expect(first.album == "First")
        #expect(first.artworkURL?.absoluteString == "https://music.example.com/lib/covers/first.jpg")
        #expect(first.duration == 61.5)
        #expect(first.sha256 == "abcdef")
        #expect(!first.hasProvisionalMetadata)
        #expect(library.tracks[1].artist == "Guest")
    }

    @Test("A manifest that breaks the spec is rejected whole")
    func rejectsInvalid() throws {
        let json = """
        {"sonus": "1.0", "library": {"id": "lib", "name": "Lib"},
         "tracks": [{"id": "t", "title": "T", "url": "http://music.example.com/t.mp3"}]}
        """
        let manifestURL = try #require(URL(string: "https://music.example.com/sonus.json"))
        #expect(throws: SourceLoadError.self) {
            try ManifestLoader.library(from: Data(json.utf8), manifestURL: manifestURL)
        }
        #expect(throws: SourceLoadError.notAManifest) {
            try ManifestLoader.library(from: Data("<html></html>".utf8), manifestURL: manifestURL)
        }
    }
}
