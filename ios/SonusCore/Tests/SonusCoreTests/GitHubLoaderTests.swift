import Foundation
import Testing
@testable import SonusCore

/// A fake GitHub (API, raw and media hosts under one local server) for end-to-end listing tests.
final class MockGitHub: @unchecked Sendable {
    static let token = "test-token"
    static let audio = Data((0..<20_000).map { UInt8(($0 * 7) % 256) })
    static let lfsAudio = Data((0..<30_000).map { UInt8(($0 * 13) % 256) })
    static var lfsPointer: Data {
        let oid = String(repeating: "c0", count: 32)
        return Data("version https://git-lfs.github.com/spec/v1\noid sha256:\(oid)\nsize \(lfsAudio.count)\n".utf8)
    }

    /// Path → content of the files in the repository.
    var files: [String: Data] = [:]
    var lfsFiles: [String: Data] = [:]
    var requireToken = true
    var truncated = false
    var forcedStatus: Reply?

    struct Reply: Sendable {
        var status: Int
        var headers: [String: String] = [:]
    }

    private(set) var server: MockHTTPServer!

    init() throws {
        server = try MockHTTPServer { [unowned self] request in respond(to: request) }
    }

    var endpoints: GitHubEndpoints {
        GitHubEndpoints(
            api: server.baseURL.appendingPathComponent("api"),
            raw: server.baseURL.appendingPathComponent("raw"),
            media: server.baseURL.appendingPathComponent("media")
        )
    }

    private func respond(to request: MockHTTPServer.Request) -> MockHTTPServer.Response {
        if let forcedStatus {
            return .init(status: forcedStatus.status, headers: forcedStatus.headers)
        }
        if requireToken && request.headers["authorization"] != "token \(Self.token)" {
            return .notFound() // GitHub hides private repositories from anonymous requests.
        }
        let path = request.path.removingPercentEncoding ?? request.path
        if path.hasPrefix("/api/") {
            return respondToAPI(path: path, request: request)
        }
        return respondToFile(path: path, request: request)
    }

    private func respondToAPI(path: String, request: MockHTTPServer.Request) -> MockHTTPServer.Response {
        switch path {
        case "/api/repos/octo/songs":
            return .json(#"{"name": "songs", "default_branch": "main", "private": true}"#)
        case "/api/repos/octo/songs/git/trees/main":
            return .json(treeJSON())
        case "/api/repos/octo/songs/git/trees/main-sha":
            return .json(rootFolderJSON())
        case "/api/repos/octo/songs/git/trees/sub-sha":
            return .json(subtreeJSON())
        case "/api/repos/octo/songs/contents/sonus.json":
            guard request.headers["accept"] == "application/vnd.github.raw+json", let manifest = files["sonus.json"] else {
                return .notFound()
            }
            return .init(status: 200, headers: ["Content-Type": "application/vnd.github.raw+json"], body: manifest)
        default:
            return .notFound()
        }
    }

    private func respondToFile(path: String, request: MockHTTPServer.Request) -> MockHTTPServer.Response {
        if path.hasPrefix("/raw/octo/songs/main/") {
            let file = String(path.dropFirst("/raw/octo/songs/main/".count))
            if lfsFiles[file] != nil {
                return .init(status: 200, body: Self.lfsPointer)
            }
            return files[file].map { .file($0, for: request) } ?? .notFound()
        }
        if path.hasPrefix("/media/octo/songs/main/") {
            let file = String(path.dropFirst("/media/octo/songs/main/".count))
            return (lfsFiles[file] ?? files[file]).map { .file($0, for: request) } ?? .notFound()
        }
        return .notFound()
    }

    private func entries() -> [(path: String, size: Int)] {
        files.map { ($0.key, $0.value.count) } + lfsFiles.keys.map { ($0, Self.lfsPointer.count) }
    }

    /// The recursive listing of `main`; empty and truncated when `truncated` is set.
    private func treeJSON() -> String {
        if truncated {
            return #"{"sha": "main-sha", "truncated": true, "tree": []}"#
        }
        let blobs = entries().map { blob($0.path, size: $0.size) }
        return #"{"sha": "main-sha", "truncated": false, "tree": ["# + blobs.joined(separator: ",") + "]}"
    }

    /// The root folder alone: top-level files plus `Folder`.
    private func rootFolderJSON() -> String {
        let top = entries().filter { !$0.path.contains("/") }.map { blob($0.path, size: $0.size) }
        let listing = (top + [folder("Folder", sha: "sub-sha")]).joined(separator: ",")
        return #"{"sha": "main-sha", "truncated": false, "tree": ["# + listing + "]}"
    }

    private func subtreeJSON() -> String {
        let inner = entries().filter { $0.path.hasPrefix("Folder/") }
            .map { blob(String($0.path.dropFirst("Folder/".count)), size: $0.size) }
        return #"{"sha": "sub-sha", "truncated": false, "tree": ["# + inner.joined(separator: ",") + "]}"
    }

    private func blob(_ path: String, size: Int) -> String {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"path": "\#(escaped)", "mode": "100644", "type": "blob", "sha": "sha-\#(size)", "size": \#(size)}"#
    }

    private func folder(_ path: String, sha: String) -> String {
        #"{"path": "\#(path)", "mode": "040000", "type": "tree", "sha": "\#(sha)"}"#
    }
}

@Suite("GitHub library loading")
struct GitHubLoaderTests {
    static func load(_ github: MockGitHub, token: String? = MockGitHub.token) async throws -> LoadedLibrary {
        let repo = try #require(GitHubRepository.parse("octo/songs"))
        let client = StreamingHTTPClient()
        defer { client.invalidate() }
        return try await GitHubLibraryLoader(client: client, endpoints: github.endpoints).load(repo, token: token)
    }

    @Test("A repository without sonus.json is listed from its tree, LFS pointers included")
    func zeroSetupListing() async throws {
        let github = try MockGitHub()
        defer { github.server.stop() }
        github.files = ["Morning Raga - (Example.Fm).mp3": MockGitHub.audio, "README.md": Data("# Songs".utf8)]
        github.lfsFiles = ["Folder/सुबह, Tune.mp3": MockGitHub.lfsAudio]

        let library = try await Self.load(github)
        #expect(library.name == "songs")
        #expect(library.tracks.map(\.remoteID) == ["Folder/सुबह, Tune.mp3", "Morning Raga - (Example.Fm).mp3"])

        let lfs = library.tracks[0]
        #expect(lfs.url.path.hasPrefix("/media/octo/songs/main/"))
        #expect(lfs.url.absoluteString.hasSuffix("/Folder/%E0%A4%B8%E0%A5%81%E0%A4%AC%E0%A4%B9%2C%20Tune.mp3"))
        #expect(lfs.size == Int64(MockGitHub.lfsAudio.count))
        #expect(lfs.sha256 == String(repeating: "c0", count: 32))

        let plain = library.tracks[1]
        #expect(plain.title == "Morning Raga")
        #expect(plain.url.path.hasPrefix("/raw/octo/songs/main/"))
        #expect(plain.hasProvisionalMetadata)

        // Every request carried the token: the API, raw and media hosts are all allowed here.
        #expect(github.server.requests.allSatisfy { $0.headers["authorization"] == "token \(MockGitHub.token)" })

        // The LFS track streams its real audio, ranged and authorized.
        let client = StreamingHTTPClient()
        defer { client.invalidate() }
        let authorization = RequestAuthorization.gitHub(token: MockGitHub.token, endpoints: github.endpoints)
        let (data, head) = try await client.data(lfs.url, range: ByteRange(lowerBound: 100, upperBound: 199), authorization: authorization)
        #expect(head.statusCode == 206)
        #expect(data == MockGitHub.lfsAudio.subdata(in: 100..<200))
    }

    @Test("sonus.json in the repository is used, read through the contents API")
    func manifestInRepository() async throws {
        let github = try MockGitHub()
        defer { github.server.stop() }
        github.files = [
            "sonus.json": Data("""
            {"sonus": "1.0", "library": {"id": "lib", "name": "Octo's songs"},
             "tracks": [{"id": "t1", "title": "Tagged Title", "artist": "Octo", "url": "audio/one.mp3"}]}
            """.utf8),
            "audio/one.mp3": MockGitHub.audio
        ]

        let library = try await Self.load(github)
        #expect(library.name == "Octo's songs")
        #expect(library.tracks.map(\.title) == ["Tagged Title"])
        #expect(library.tracks.first?.url.path == "/raw/octo/songs/main/audio/one.mp3")
        #expect(library.tracks.first?.hasProvisionalMetadata == false)
    }

    @Test("A truncated tree is walked folder by folder")
    func truncatedTree() async throws {
        let github = try MockGitHub()
        defer { github.server.stop() }
        github.truncated = true
        github.files = ["Top.mp3": MockGitHub.audio, "Folder/Inner.mp3": MockGitHub.audio]

        let library = try await Self.load(github)
        #expect(Set(library.tracks.map(\.remoteID)) == ["Top.mp3", "Folder/Inner.mp3"])
        #expect(library.warnings.isEmpty)
    }

    @Test("Public repositories list without a token")
    func publicRepository() async throws {
        let github = try MockGitHub()
        defer { github.server.stop() }
        github.requireToken = false
        github.files = ["a.mp3": MockGitHub.audio]

        let library = try await Self.load(github, token: nil)
        #expect(library.tracks.count == 1)
        #expect(github.server.requests.allSatisfy { $0.headers["authorization"] == nil })
    }

    @Test("Failures map to GitHub's meaning", arguments: [
        (MockGitHub.Reply(status: 401), SourceLoadError.github(.unauthorized)),
        (MockGitHub.Reply(status: 403, headers: ["X-RateLimit-Remaining": "5"]), SourceLoadError.github(.forbidden)),
        (MockGitHub.Reply(status: 429, headers: ["Retry-After": "120"]), SourceLoadError.github(.rateLimited(retryAfter: 120))),
        (MockGitHub.Reply(status: 404), SourceLoadError.github(.notFound(hasToken: true)))
    ])
    func failures(reply: MockGitHub.Reply, expected: SourceLoadError) async throws {
        let github = try MockGitHub()
        defer { github.server.stop() }
        github.forcedStatus = reply
        await #expect(throws: expected) {
            try await Self.load(github)
        }
    }

    @Test("A private repository without a token reads as not found")
    func missingToken() async throws {
        let github = try MockGitHub()
        defer { github.server.stop() }
        await #expect(throws: SourceLoadError.github(.notFound(hasToken: false))) {
            try await Self.load(github, token: nil)
        }
    }
}

@Suite("Manifest loading")
struct ManifestLoaderTests {
    @Test("A manifest is fetched, validated and mapped")
    func loads() async throws {
        let manifest = Data("""
        {"sonus": "1.0", "library": {"id": "lib", "name": "Local"},
         "tracks": [{"id": "t1", "title": "One", "url": "one.m4a", "duration": 3.5}]}
        """.utf8)
        let server = try MockHTTPServer { request in
            request.path == "/music/sonus.json" ? .json(String(data: manifest, encoding: .utf8) ?? "") : .notFound()
        }
        defer { server.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let url = server.baseURL.appendingPathComponent("music/sonus.json")
        let library = try await ManifestLoader(client: client).load(from: url)
        #expect(library.name == "Local")
        #expect(library.tracks.first?.url == server.baseURL.appendingPathComponent("music/one.m4a"))

        await #expect(throws: SourceLoadError.http(404)) {
            try await ManifestLoader(client: client).load(from: server.baseURL.appendingPathComponent("missing.json"))
        }
    }
}
