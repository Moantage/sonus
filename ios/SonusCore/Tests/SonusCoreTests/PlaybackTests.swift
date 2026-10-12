import Foundation
import Testing
@testable import SonusCore

@Suite("Stream or local")
struct PlaybackRoutingTests {
    static let localFile = URL(fileURLWithPath: "/tmp/ImportedSongs/A.mp3")

    @Test("A file on the device always wins, so downloads play offline")
    func localWins() throws {
        let remote = try #require(URL(string: "https://music.example.com/a.mp3"))
        #expect(PlaybackRouter.route(localFile: Self.localFile, localFileExists: true, remoteURL: remote) == .localFile(Self.localFile))
        #expect(PlaybackRouter.route(localFile: Self.localFile, localFileExists: true, remoteURL: nil) == .localFile(Self.localFile))
    }

    @Test("Without a local file the song streams from its source")
    func streams() throws {
        let remote = try #require(URL(string: "http://192.168.1.20/a.mp3"))
        #expect(PlaybackRouter.route(localFile: Self.localFile, localFileExists: false, remoteURL: remote) == .stream(remote))
    }

    @Test("Missing files and insecure addresses can't play")
    func unavailable() throws {
        #expect(PlaybackRouter.route(localFile: Self.localFile, localFileExists: false, remoteURL: nil) == .unavailable(.missingFile))
        let insecure = try #require(URL(string: "http://music.example.com/a.mp3"))
        #expect(PlaybackRouter.route(localFile: Self.localFile, localFileExists: false, remoteURL: insecure)
            == .unavailable(.blockedURL(insecure)))
    }
}

@Suite("Audio file types")
struct AudioFileTypeTests {
    struct NamingCase: Sendable, CustomTestStringConvertible {
        let url: String
        let mimeType: String?
        let fileExtension: String

        var testDescription: String { "\(url) \(mimeType ?? "-") → \(fileExtension)" }
    }

    @Test("Local file names keep a playable extension", arguments: [
        NamingCase(url: "https://x.example/a/Song.MP3", mimeType: nil, fileExtension: "mp3"),
        NamingCase(url: "https://x.example/stream?id=4", mimeType: "audio/mp4", fileExtension: "m4a"),
        NamingCase(url: "https://x.example/stream?id=4", mimeType: "audio/mpeg; charset=binary", fileExtension: "mp3"),
        NamingCase(url: "https://x.example/a.ogg", mimeType: "audio/flac", fileExtension: "flac"),
        NamingCase(url: "https://x.example/stream", mimeType: nil, fileExtension: "mp3")
    ])
    func localFileName(naming: NamingCase) throws {
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let name = AudioFileType.localFileName(songID: id, url: try #require(URL(string: naming.url)), mimeType: naming.mimeType)
        #expect(name == "6F9619FF-8B86-D011-B42D-00C04FC964FF.\(naming.fileExtension)")
    }

    @Test("AVFoundation gets a Uniform Type Identifier for each playable extension")
    func uniformTypes() {
        #expect(AudioFileType.uniformType(forExtension: "MP3") == "public.mp3")
        #expect(AudioFileType.uniformType(forExtension: "m4a") == "com.apple.m4a-audio")
        #expect(AudioFileType.uniformType(forExtension: "flac") == "org.xiph.flac")
        #expect(AudioFileType.uniformType(forExtension: "txt") == nil)
        #expect(AudioFileType.playableExtensions.allSatisfy { AudioFileType.mimeType(forExtension: $0) != nil })
        #expect(!AudioFileType.isPlayable(fileExtension: "ogg"))
    }
}

@Suite("Titles from file names")
struct TitleCleanerTests {
    @Test("Site tags, underscores and dashes are cleaned up", arguments: [
        ("Morning Raga - (Example.Fm).mp3", "Morning Raga"),
        ("Chalo-Ghar-Chalen-Ham(PagalWorld).mp3", "Chalo Ghar Chalen Ham"),
        ("सुबह_की_धुन,_Morning_Tune_I_Live.mp3", "सुबह की धुन, Morning Tune I Live"),
        ("Track 01 [320kbps] www.songs.example.com.m4a", "Track 01"),
        ("Song (Live).mp3", "Song (Live)"),
        ("St.Louis Blues.mp3", "St.Louis Blues"),
        ("(PagalWorld).mp3", "(PagalWorld)"),
        ("folder/Plain Title.flac", "Plain Title")
    ])
    func cleans(fileName: String, title: String) {
        #expect(TrackTitleCleaner.title(fromFileName: fileName) == title)
    }
}

@Suite("Playback error messages")
struct ErrorMessageTests {
    @Test("The most specific message in the chain wins")
    func chain() {
        let chain = [
            ErrorLink(domain: StreamingErrorMessages.avFoundationDomain, code: -11800),
            ErrorLink(domain: StreamingErrorMessages.urlDomain, code: -1009)
        ]
        #expect(StreamingErrorMessages.message(for: chain) == StreamingErrorMessages.offline)
    }

    @Test("Known failures get actionable messages", arguments: [
        (StreamingErrorMessages.avFoundationDomain, -11850, StreamingErrorMessages.noRangeSupport),
        (StreamingErrorMessages.urlDomain, -1004, StreamingErrorMessages.unreachable),
        (StreamingErrorMessages.urlDomain, -1022, StreamingErrorMessages.blocked),
        (StreamingErrorMessages.coreMediaDomain, -12938, StreamingErrorMessages.notFound),
        ("SomeOtherDomain", 1, StreamingErrorMessages.generic)
    ])
    func known(domain: String, code: Int, message: String) {
        #expect(StreamingErrorMessages.message(for: [ErrorLink(domain: domain, code: code)]) == message)
    }

    @Test("Sonus's own errors show their message")
    func ownMessage() {
        let link = ErrorLink(domain: StreamingErrorMessages.sonusDomain, code: 401, message: "Token expired.")
        #expect(StreamingErrorMessages.message(for: [link]) == "Token expired.")
    }
}
