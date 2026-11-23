import Foundation
import Testing
@testable import SonusCore

@Suite("MD5 for Subsonic tokens")
struct MD5Tests {
    @Test("RFC 1321 test vectors", arguments: [
        ("", "d41d8cd98f00b204e9800998ecf8427e"),
        ("a", "0cc175b9c0f1b6a831c399e269772661"),
        ("abc", "900150983cd24fb0d6963f7d28e17f72"),
        ("message digest", "f96b697d7cb7938d525a2f31aaf161d0"),
        ("abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b"),
        ("12345678901234567890123456789012345678901234567890123456789012345678901234567890",
         "57edf4a22be3c955ac49da2e2107b67a")
    ])
    func vectors(input: String, expected: String) {
        #expect(MD5.hex(input) == expected)
    }

    @Test("The Subsonic documentation's token example")
    func subsonicExample() {
        // From the Subsonic API docs: password "sesame", salt "c19b2d".
        let credentials = OpenSubsonicCredentials(username: "joe", password: "sesame")
        #expect(credentials.tokenParameters(salt: "c19b2d") == ["u": "joe", "t": "26719a1196d2a940705a59634eb18eab", "s": "c19b2d"])
    }
}

@Suite("OpenSubsonic credentials and URLs")
struct OpenSubsonicURLTests {
    @Test("Credentials survive the Keychain round trip and never print the password")
    func credentialsRoundTrip() {
        let credentials = OpenSubsonicCredentials(username: "joe", password: "p@ss \"word\"")
        #expect(OpenSubsonicCredentials(secret: credentials.encodedSecret) == credentials)
        #expect(OpenSubsonicCredentials(secret: "plain-token") == nil)
        #expect(!credentials.description.contains("p@ss"))
        let authorization = credentials.authorization(for: URL(string: "https://music.example.com")!, salt: "abc")
        #expect(authorization?.description.contains(MD5.hex("p@ss \"word\"abc")) == false)
    }

    @Test("Server addresses are normalised", arguments: [
        ("music.example.com", "https://music.example.com"),
        ("https://music.example.com/", "https://music.example.com"),
        ("https://example.com/navidrome/rest/", "https://example.com/navidrome"),
        ("192.168.1.20:4533", "http://192.168.1.20:4533"),
        ("nas.local:4533/music", "http://nas.local:4533/music"),
        ("http://music.example.com", "http://music.example.com")
    ])
    func normalise(input: String, expected: String) {
        #expect(OpenSubsonicEndpoints.serverURL(from: input)?.absoluteString == expected)
    }

    @Test("Nonsense isn't a server address", arguments: ["", "   ", "not a url", "ftp://example.com"])
    func rejectsNonsense(input: String) {
        #expect(OpenSubsonicEndpoints.serverURL(from: input) == nil)
    }

    @Test("Endpoint URLs keep the base path and carry no credentials")
    func endpoints() throws {
        let endpoints = OpenSubsonicEndpoints(serverURL: try #require(URL(string: "https://example.com/navidrome")))
        let stream = try #require(endpoints.stream(id: "a b&c"))
        #expect(stream.path == "/navidrome/rest/stream")
        #expect(stream.query == "c=Sonus&format=raw&id=a%20b%26c&v=1.16.1")
    }

    @Test("Query authorization is added only for the server's host and replaces stale values")
    func queryAuthorization() throws {
        let authorization = RequestAuthorization.query(["u": "jo+e", "t": "token", "s": "salt"], hosts: ["music.example.com"])
        var request = URLRequest(url: try #require(URL(string: "https://music.example.com/rest/stream?id=1&t=old")))
        authorization.authorize(&request)
        #expect(request.url?.query == "id=1&s=salt&t=token&u=jo%2Be")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(authorization.headers(for: try #require(request.url)).isEmpty)

        authorization.authorize(&request)
        #expect(request.url?.query == "id=1&s=salt&t=token&u=jo%2Be")

        var other = URLRequest(url: try #require(URL(string: "https://cdn.example.com/file.mp3")))
        authorization.authorize(&other)
        #expect(other.url?.query == nil)

        var plainHTTP = URLRequest(url: try #require(URL(string: "http://music.example.com/rest/ping")))
        authorization.authorize(&plainHTTP)
        #expect(plainHTTP.url?.query == nil)
    }

    @Test("Server errors read as plain words")
    func errorMessages() {
        #expect(SourceLoadError.openSubsonic(OpenSubsonicError(code: 40, message: "Wrong username or password")).description
                == "Wrong username or password.")
        #expect(OpenSubsonicError(code: 41, message: nil).description.contains("token authentication"))
        #expect(OpenSubsonicError(code: 0, message: "Boom").description == "The server said: Boom")
    }
}

/// A fake Navidrome-style server on a local port.
final class MockSubsonic: @unchecked Sendable {
    static let username = "joe"
    static let password = "sesame"

    var albumPages: [[String]] = [["al-1", "al-2"]]
    var albums: [String: String] = [:]
    var serverType = "navidrome"

    private(set) var server: MockHTTPServer!

    init() throws {
        server = try MockHTTPServer { [unowned self] request in respond(to: request) }
    }

    var credentials: OpenSubsonicCredentials {
        OpenSubsonicCredentials(username: Self.username, password: Self.password)
    }

    func stop() {
        server.stop()
    }

    private func respond(to request: MockHTTPServer.Request) -> MockHTTPServer.Response {
        let query = Self.query(of: request.target)
        guard request.path.hasPrefix("/music/rest/") else { return .notFound() }
        guard let salt = query["s"], query["u"] == Self.username,
              query["t"] == MD5.hex(Self.password + salt), query["p"] == nil else {
            return ok(#""status": "failed", "error": {"code": 40, "message": "Wrong username or password"}"#)
        }
        switch String(request.path.dropFirst("/music/rest/".count)) {
        case "ping":
            return ok(#""status": "ok""#)
        case "getAlbumList2":
            let offset = Int(query["offset"] ?? "0") ?? 0
            let page = offset == 0 ? 0 : 1
            let ids = page < albumPages.count ? albumPages[page] : []
            let list = ids.map { #"{"id": "\#($0)", "name": "\#($0)"}"# }.joined(separator: ",")
            return ok(#""status": "ok", "albumList2": {"album": [\#(list)]}"#)
        case "getAlbum":
            guard let id = query["id"], let body = albums[id] else {
                return ok(#""status": "failed", "error": {"code": 70, "message": "Not found"}"#)
            }
            return ok(#""status": "ok", "album": \#(body)"#)
        default:
            return .notFound()
        }
    }

    private func ok(_ body: String) -> MockHTTPServer.Response {
        .json(#"{"subsonic-response": {\#(body), "version": "1.16.1", "type": "\#(serverType)", "openSubsonic": true}}"#)
    }

    static func query(of target: String) -> [String: String] {
        let query = target.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        var values: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            values[parts[0]] = parts.count > 1 ? parts[1].removingPercentEncoding : ""
        }
        return values
    }
}

@Suite("OpenSubsonic library loading")
struct OpenSubsonicLoaderTests {
    private func baseURL(_ mock: MockSubsonic) -> URL {
        mock.server.baseURL.appendingPathComponent("music")
    }

    @Test("Lists every album's songs with stream and artwork URLs that hold no secrets")
    func listsLibrary() async throws {
        let mock = try MockSubsonic()
        defer { mock.stop() }
        mock.albums = [
            "al-1": #"""
            {"id": "al-1", "name": "First", "artist": "Band", "coverArt": "al-1",
             "song": [{"id": "s1", "title": "One", "artist": "Band", "album": "First", "duration": 181,
                       "size": 4000000, "suffix": "mp3", "contentType": "audio/mpeg"},
                      {"id": 2, "title": "", "path": "Band/First/02 - Two.flac", "suffix": "flac", "duration": "200"}]}
            """#,
            // An old server's single song as a bare object, in a format iOS can't play.
            "al-2": #"{"id": "al-2", "name": "Second", "song": {"id": "s3", "title": "Three", "suffix": "ogg", "size": 10}}"#
        ]
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let library = try await OpenSubsonicLoader(client: client).load(serverURL: baseURL(mock), credentials: mock.credentials)
        #expect(library.name == "localhost")
        #expect(library.tracks.map(\.remoteID) == ["s1", "2", "s3"])

        let first = library.tracks[0]
        #expect(first.title == "One")
        #expect(first.artist == "Band")
        #expect(first.duration == 181)
        #expect(first.mimeType == "audio/mpeg")
        #expect(first.size == 4_000_000)
        #expect(first.url.path == "/music/rest/stream")
        #expect(first.url.query?.contains("format=raw") == true)
        #expect(first.artworkURL?.path == "/music/rest/getCoverArt")

        let second = library.tracks[1]
        #expect(second.title == TrackTitleCleaner.title(fromFileName: "02 - Two.flac"))
        #expect(second.album == "First")
        #expect(second.duration == 200)
        #expect(second.mimeType == "audio/flac")

        let third = library.tracks[2]
        #expect(third.url.query?.contains("format=mp3") == true)
        #expect(third.mimeType == "audio/mpeg")
        #expect(third.size == nil)
        #expect(library.warnings.count == 1)

        for track in library.tracks {
            let query = MockSubsonic.query(of: track.url.absoluteString)
            #expect(query["t"] == nil && query["s"] == nil && query["u"] == nil && query["p"] == nil)
        }
        // Every request used one salted token, never the password.
        for request in mock.server.requests {
            #expect(!request.target.contains(MockSubsonic.password))
        }
    }

    @Test("Pages through more albums than fit in one response")
    func pagesAlbums() async throws {
        let mock = try MockSubsonic()
        defer { mock.stop() }
        let firstPage = (0..<OpenSubsonicLoader.pageSize).map { "al-\($0)" }
        mock.albumPages = [firstPage, ["al-last"]]
        mock.albums = Dictionary(uniqueKeysWithValues: (firstPage + ["al-last"]).map { id in
            (id, #"{"id": "\#(id)", "name": "\#(id)", "song": [{"id": "song-\#(id)", "title": "\#(id)", "suffix": "mp3"}]}"#)
        })
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let library = try await OpenSubsonicLoader(client: client).load(serverURL: baseURL(mock), credentials: mock.credentials)
        #expect(library.tracks.count == OpenSubsonicLoader.pageSize + 1)
        #expect(library.tracks.last?.remoteID == "song-al-last")
        #expect(library.warnings.isEmpty)
    }

    @Test("A wrong password is reported in plain words")
    func wrongPassword() async throws {
        let mock = try MockSubsonic()
        defer { mock.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let wrong = OpenSubsonicCredentials(username: MockSubsonic.username, password: "nope")
        await #expect(throws: SourceLoadError.openSubsonic(OpenSubsonicError(code: 40, message: "Wrong username or password"))) {
            try await OpenSubsonicLoader(client: client).verify(serverURL: baseURL(mock), credentials: wrong)
        }
    }

    @Test("An address that isn't a music server says so")
    func notAMusicServer() async throws {
        let mock = try MockSubsonic()
        defer { mock.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        await #expect(throws: SourceLoadError.notAMusicServer) {
            try await OpenSubsonicLoader(client: client).verify(serverURL: mock.server.baseURL, credentials: mock.credentials)
        }
    }

    @Test("Albums that fail are skipped with a warning")
    func failedAlbum() async throws {
        let mock = try MockSubsonic()
        defer { mock.stop() }
        mock.albums = ["al-1": #"{"id": "al-1", "song": [{"id": "s1", "title": "One", "suffix": "m4a"}]}"#]
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let library = try await OpenSubsonicLoader(client: client).load(serverURL: baseURL(mock), credentials: mock.credentials)
        #expect(library.tracks.map(\.remoteID) == ["s1"])
        #expect(library.warnings == ["1 album couldn't be read and will be tried again next refresh."])
    }

    @Test("Streaming a song sends the token only to the server")
    func streamCarriesToken() async throws {
        let mock = try MockSubsonic()
        defer { mock.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let authorization = try #require(mock.credentials.authorization(for: baseURL(mock)))
        let ping = try #require(OpenSubsonicEndpoints(serverURL: baseURL(mock)).ping)
        _ = try await client.data(ping, authorization: authorization)
        let query = MockSubsonic.query(of: try #require(mock.server.requests.last).target)
        #expect(query["u"] == MockSubsonic.username)
        #expect(query["t"] == MD5.hex(MockSubsonic.password + (query["s"] ?? "")))
    }
}
