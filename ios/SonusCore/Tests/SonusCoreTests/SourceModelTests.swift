import Foundation
import Testing
@testable import SonusCore

@Suite("Music sources")
struct SourceModelTests {
    static let manifestURL = URL(string: "https://music.example.com/sonus.json")!

    @Test("Only manifest and GitHub sources are implemented; the server kinds are reserved")
    func supportedKinds() {
        #expect(MusicSource.Kind.manifest.isSupported)
        #expect(MusicSource.Kind.github.isSupported)
        #expect(!MusicSource.Kind.sonusServer.isSupported)
        #expect(!MusicSource.Kind.openSubsonic.isSupported)
    }

    @Test("A source list round-trips through JSON without any secret in it")
    func roundTrip() throws {
        var source = MusicSource.manifest(url: Self.manifestURL, name: "Home")
        source.credentialKey = MusicSource.defaultCredentialKey(for: source.id)
        let repo = try #require(GitHubRepository(owner: "octo", name: "songs", branch: "main"))
        let list = SourceList(sources: [source, .github(repo)])

        let data = try list.encoded()
        let decoded = try SourceList.decode(from: data)
        #expect(decoded.sources.map(\.id) == list.sources.map(\.id))
        #expect(decoded.sources[1].github == repo)
        #expect(decoded.sources[0].credentialKey == "source.\(source.id.uuidString).credential")
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("token"))
    }

    @Test("An unknown source kind is skipped instead of failing the whole list")
    func lenientDecoding() throws {
        let json = """
        {"version": 1, "sources": [
          {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Future", "kind": "spaceRadio",
           "url": "https://x.example", "addedAt": "2026-10-11T10:00:00Z"},
          {"id": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Home", "kind": "manifest",
           "url": "https://music.example.com/sonus.json", "addedAt": "2026-10-11T10:00:00Z"}
        ]}
        """
        let list = try SourceList.decode(from: Data(json.utf8))
        #expect(list.sources.map(\.name) == ["Home"])
    }

    @Test("Adding the same library again matches the existing source")
    func sameLibrary() throws {
        let first = MusicSource.manifest(url: Self.manifestURL)
        let again = MusicSource.manifest(url: Self.manifestURL, name: "Other name")
        #expect(first.isSameLibrary(as: again))

        let repo = try #require(GitHubRepository(owner: "Octo", name: "Songs"))
        let pinned = try #require(GitHubRepository(owner: "octo", name: "songs", branch: "main"))
        let other = try #require(GitHubRepository(owner: "octo", name: "songs", subfolder: "live"))
        #expect(MusicSource.github(repo).isSameLibrary(as: .github(pinned)))
        #expect(!MusicSource.github(repo).isSameLibrary(as: .github(other)))
        #expect(!first.isSameLibrary(as: .github(repo)))
    }

    @Test("Launch arguments are read as -Name value pairs", arguments: [
        (["app", "-SonusDebugManifestURL", "http://localhost:8765/sonus.json"], "http://localhost:8765/sonus.json"),
        (["app", "-SonusDebugManifestURL"], nil),
        (["app", "-SonusDebugManifestURL", "-Other"], nil),
        (["app"], nil)
    ])
    func launchArguments(arguments: [String], expected: String?) {
        #expect(LaunchArguments.value(for: "SonusDebugManifestURL", in: arguments) == expected)
    }

    @Test("Credentials embedded in a URL are removed before it leaves the device")
    func removingCredentials() throws {
        let url = try #require(URL(string: "https://user:secret@music.example.com/a.mp3?x=1"))
        #expect(url.removingCredentials.absoluteString == "https://music.example.com/a.mp3?x=1")
        #expect(Self.manifestURL.removingCredentials == Self.manifestURL)
    }
}

@Suite("Request authorization")
struct AuthorizationTests {
    @Test("A GitHub token only goes to GitHub's API, raw and media hosts over https", arguments: [
        ("https://api.github.com/repos/o/r", true),
        ("https://raw.githubusercontent.com/o/r/main/a.mp3", true),
        ("https://media.githubusercontent.com/media/o/r/main/a.mp3", true),
        ("https://API.GITHUB.COM/repos/o/r", true),
        ("http://api.github.com/repos/o/r", false),
        ("https://github.com/o/r", false),
        ("https://api.github.com.evil.example/repos", false),
        ("https://objects.githubusercontent.com/x", false),
        ("https://evil.example/?u=api.github.com", false)
    ])
    func gitHubHosts(url: String, receivesToken: Bool) throws {
        let authorization = RequestAuthorization.gitHub(token: "test-token")
        let parsed = try #require(URL(string: url))
        #expect(authorization.applies(to: parsed) == receivesToken)
        #expect(authorization.headers(for: parsed).isEmpty == !receivesToken)
    }

    @Test("Plain http only carries a secret to an allowed host on the local network")
    func localHTTP() throws {
        let authorization = RequestAuthorization.bearer("secret", hosts: ["nas.local", "music.example.com"])
        #expect(authorization.applies(to: try #require(URL(string: "http://nas.local/a.mp3"))))
        #expect(!authorization.applies(to: try #require(URL(string: "http://music.example.com/a.mp3"))))
        #expect(authorization.headers(for: try #require(URL(string: "http://nas.local/a.mp3"))) == ["Authorization": "Bearer secret"])
    }

    @Test("Printing an authorization never shows the secret")
    func redacted() {
        let authorization = RequestAuthorization.gitHub(token: "ghp_supersecret")
        #expect(!authorization.description.contains("supersecret"))
        #expect(!String(describing: authorization).contains("supersecret"))
    }

    @Test("Redirects drop the secret for other hosts and refuse insecure targets")
    func redirects() throws {
        let authorization = RequestAuthorization.gitHub(token: "t")
        var proposed = URLRequest(url: try #require(URL(string: "https://objects.githubusercontent.com/blob")))
        proposed.setValue("token t", forHTTPHeaderField: "Authorization")
        let followed = try #require(RedirectPolicy.follow(proposed, authorization: authorization, headers: ["Range": "bytes=0-1"]))
        #expect(followed.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(followed.value(forHTTPHeaderField: "Range") == "bytes=0-1")

        let sameHost = URLRequest(url: try #require(URL(string: "https://raw.githubusercontent.com/o/r/main/b.mp3")))
        let kept = try #require(RedirectPolicy.follow(sameHost, authorization: authorization, headers: [:]))
        #expect(kept.value(forHTTPHeaderField: "Authorization") == "token t")

        let downgrade = URLRequest(url: try #require(URL(string: "http://raw.githubusercontent.com/o/r/main/b.mp3")))
        #expect(RedirectPolicy.follow(downgrade, authorization: authorization, headers: [:]) == nil)
    }

    @Test("Stream URLs swap their scheme so the app's loader can add headers", arguments: [
        "https://raw.githubusercontent.com/o/r/main/My%20Song.mp3",
        "http://192.168.1.20:8080/music/a.flac"
    ])
    func streamURLs(original: String) throws {
        let url = try #require(URL(string: original))
        let wrapped = try #require(AuthenticatedStreamURL.wrap(url))
        #expect(AuthenticatedStreamURL.isWrapped(wrapped))
        #expect(wrapped.scheme != url.scheme)
        #expect(wrapped.pathExtension == url.pathExtension)
        #expect(AuthenticatedStreamURL.unwrap(wrapped) == url)
        #expect(AuthenticatedStreamURL.wrap(try #require(URL(string: "ftp://x.example/a.mp3"))) == nil)
    }
}
