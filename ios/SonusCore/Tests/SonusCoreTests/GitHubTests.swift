import Foundation
import Testing
@testable import SonusCore

@Suite("GitHub repositories")
struct GitHubRepositoryTests {
    @Test("owner/repo[/folder][@branch] parses", arguments: [
        ("octo/songs", "octo/songs"),
        ("octo/songs@main", "octo/songs@main"),
        ("octo/songs@feature/new-mix", "octo/songs@feature/new-mix"),
        (" octo/my.songs/albums/2024/@main ", "octo/my.songs/albums/2024@main")
    ])
    func parses(text: String, normalized: String) throws {
        let repo = try #require(GitHubRepository.parse(text))
        #expect(repo.description == normalized)
    }

    @Test("Parsed parts land in the right fields")
    func parts() throws {
        let repo = try #require(GitHubRepository.parse("octo/my.songs/albums/2024@feature/x"))
        #expect(repo.owner == "octo")
        #expect(repo.name == "my.songs")
        #expect(repo.subfolder == "albums/2024")
        #expect(repo.branch == "feature/x")
    }

    @Test("Invalid names, branches and folders are refused", arguments: [
        "octo", "octo/", "/songs", "octo/songs@", "-octo/songs", "octo/so ngs", "octo/songs@a..b",
        "octo/songs@bad:ref", "octo/songs/../secrets", "oct o/songs"
    ])
    func refuses(text: String) {
        #expect(GitHubRepository.parse(text) == nil)
    }
}

@Suite("GitHub URLs")
struct GitHubURLTests {
    static func repo() throws -> GitHubRepository {
        try #require(GitHubRepository.parse("octo/songs"))
    }

    @Test("Each path segment is percent-encoded, spaces, brackets, commas and non-ASCII included", arguments: [
        ("Morning Raga - (Example.Fm).mp3", "Morning%20Raga%20-%20%28Example.Fm%29.mp3"),
        ("Chalo-Ghar(PagalWorld).mp3", "Chalo-Ghar%28PagalWorld%29.mp3"),
        ("सुबह_की,_Tune.mp3", "%E0%A4%B8%E0%A5%81%E0%A4%AC%E0%A4%B9_%E0%A4%95%E0%A5%80%2C_Tune.mp3"),
        ("a/b c/d#?.mp3", "a/b%20c/d%23%3F.mp3")
    ])
    func encodesPaths(path: String, encoded: String) throws {
        let repo = try Self.repo()
        #expect(GitHubPath.encode(path) == encoded)
        let raw = try #require(GitHubEndpoints.github.raw(repo, ref: "main", path: path))
        #expect(raw.absoluteString == "https://raw.githubusercontent.com/octo/songs/main/\(encoded)")
        // The stable ID round-trips: the raw URL maps back to the exact repository path.
        #expect(GitHubEndpoints.github.repositoryPath(ofRawURL: raw, repo: repo, ref: "main") == path)
    }

    @Test("API, contents and media URLs")
    func endpoints() throws {
        let repo = try Self.repo()
        let github = GitHubEndpoints.github
        #expect(github.repository(repo)?.absoluteString == "https://api.github.com/repos/octo/songs")
        #expect(github.tree(repo, ref: "main", recursive: true)?.absoluteString
            == "https://api.github.com/repos/octo/songs/git/trees/main?recursive=1")
        #expect(github.tree(repo, ref: "feature/x", recursive: false)?.absoluteString
            == "https://api.github.com/repos/octo/songs/git/trees/feature%2Fx")
        #expect(github.contents(repo, path: "live/sonus.json", ref: "main")?.absoluteString
            == "https://api.github.com/repos/octo/songs/contents/live/sonus.json?ref=main")
        #expect(github.media(repo, ref: "main", path: "a b.mp3")?.absoluteString
            == "https://media.githubusercontent.com/media/octo/songs/main/a%20b.mp3")
        #expect(github.hosts == ["api.github.com", "raw.githubusercontent.com", "media.githubusercontent.com"])
    }

    @Test("A URL outside the repository has no repository path")
    func foreignRawURL() throws {
        let repo = try Self.repo()
        let other = try #require(URL(string: "https://raw.githubusercontent.com/octo/other/main/a.mp3"))
        #expect(GitHubEndpoints.github.repositoryPath(ofRawURL: other, repo: repo, ref: "main") == nil)
    }
}

@Suite("GitHub trees")
struct GitHubTreeTests {

    static let tree = GitTree(sha: "root", truncated: false, tree: [
        .init(path: "README.md", type: "blob", sha: "1", size: 100),
        .init(path: "b side.mp3", type: "blob", sha: "2", size: 5_000_000),
        .init(path: "A Side.M4A", type: "blob", sha: "3", size: 4_000_000),
        .init(path: "cover.jpg", type: "blob", sha: "4", size: 20_000),
        .init(path: "live", type: "tree", sha: "5"),
        .init(path: "live/Encore (Live).flac", type: "blob", sha: "6", size: 130),
        .init(path: "notes.ogg", type: "blob", sha: "7", size: 3_000)
    ])

    @Test("Only playable audio files become tracks, keyed by path, titled from the file name")
    func audioOnly() throws {
        let repo = try #require(GitHubRepository(owner: "octo", name: "songs"))
        let entries = GitHubTreeLibrary.audioEntries(in: Self.tree.tree, repository: repo)
        #expect(entries.map(\.path) == ["A Side.M4A", "b side.mp3", "live/Encore (Live).flac"])

        let track = try #require(GitHubTreeLibrary.track(for: entries[1], repository: repo, ref: "main", endpoints: .github))
        #expect(track.remoteID == "b side.mp3")
        #expect(track.title == "b side")
        #expect(track.url.absoluteString == "https://raw.githubusercontent.com/octo/songs/main/b%20side.mp3")
        #expect(track.mimeType == "audio/mpeg")
        #expect(track.size == 5_000_000)
        #expect(track.revision == "2")
        #expect(track.hasProvisionalMetadata)
    }

    @Test("A subfolder limits the listing and holds the manifest")
    func subfolder() throws {
        let repo = try #require(GitHubRepository(owner: "octo", name: "songs", subfolder: "/live/"))
        #expect(GitHubTreeLibrary.audioEntries(in: Self.tree.tree, repository: repo).map(\.path) == ["live/Encore (Live).flac"])
        #expect(GitHubTreeLibrary.manifestPath(for: repo) == "live/sonus.json")
        #expect(GitHubLibraryLoader.mayContainFiles("live", of: repo))
        #expect(!GitHubLibraryLoader.mayContainFiles("studio", of: repo))
    }

    @Test("Small audio blobs are LFS pointer candidates")
    func lfsCandidates() {
        #expect(GitHubTreeLibrary.mightBeLFSPointer(Self.tree.tree[5]))
        #expect(!GitHubTreeLibrary.mightBeLFSPointer(Self.tree.tree[1]))
    }

    @Test("Tree JSON decodes, with truncated defaulting to false")
    func decodes() throws {
        let json = """
        {"sha": "abc", "url": "https://api.github.com/x", "tree": [
          {"path": "a.mp3", "mode": "100644", "type": "blob", "sha": "1", "size": 10, "url": "u"},
          {"path": "d", "mode": "040000", "type": "tree", "sha": "2", "url": "u"}]}
        """
        let tree = try JSONDecoder().decode(GitTree.self, from: Data(json.utf8))
        #expect(!tree.truncated)
        #expect(tree.tree.count == 2)
        #expect(tree.tree[1].size == nil)
    }
}

@Suite("Git LFS pointers")
struct LFSPointerTests {
    static let oid = String(repeating: "ab", count: 32)

    @Test("A pointer file parses")
    func parses() throws {
        let text = "version https://git-lfs.github.com/spec/v1\noid sha256:\(Self.oid)\nsize 4823344\n"
        let pointer = try #require(LFSPointer.parse(Data(text.utf8)))
        #expect(pointer.oid == Self.oid)
        #expect(pointer.size == 4_823_344)
    }

    @Test("Real audio and malformed pointers are not pointers", arguments: [
        "ID3\u{3}\u{0}\u{0}\u{0}",
        "oid sha256:\(String(repeating: "ab", count: 32))\nsize 1\n",
        "version https://git-lfs.github.com/spec/v1\noid sha256:short\nsize 1\n",
        "version https://git-lfs.github.com/spec/v1\noid sha256:\(String(repeating: "ab", count: 32))\n"
    ])
    func rejects(text: String) {
        #expect(LFSPointer.parse(Data(text.utf8)) == nil)
    }
}

@Suite("GitHub errors")
struct GitHubErrorTests {
    static let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Rate limits read Retry-After or X-RateLimit-Reset")
    func rateLimits() {
        #expect(GitHubAPIError.classify(statusCode: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1000600"],
                                        hasToken: false, now: Self.now) == .rateLimited(retryAfter: 600))
        #expect(GitHubAPIError.classify(statusCode: 429, headers: ["retry-after": "30"], hasToken: true, now: Self.now)
            == .rateLimited(retryAfter: 30))
        #expect(GitHubAPIError.classify(statusCode: 429, headers: [:], hasToken: true) == .rateLimited(retryAfter: nil))
        #expect(GitHubAPIError.rateLimited(retryAfter: 600).description.contains("10 minutes"))
    }

    @Test("Auth and missing-repository failures get distinct messages", arguments: [
        (401, GitHubAPIError.unauthorized),
        (403, GitHubAPIError.forbidden),
        (404, GitHubAPIError.notFound(hasToken: true)),
        (500, GitHubAPIError.http(500))
    ])
    func statuses(status: Int, expected: GitHubAPIError) {
        #expect(GitHubAPIError.classify(statusCode: status, headers: ["X-RateLimit-Remaining": "12"], hasToken: true) == expected)
    }

    @Test("Success is not an error")
    func success() {
        #expect(GitHubAPIError.classify(statusCode: 200, headers: [:], hasToken: false) == nil)
    }
}
