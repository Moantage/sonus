import Foundation
import Testing
@testable import SonusCore

/// These tests read the same fixtures the docs site publishes and the JSON Schema check
/// validates (`spec/examples`), so the Swift models can't drift from the spec.
@Suite("Sonus Manifest")
struct ManifestTests {
    static let manifestURL = URL(string: "https://music.example.com/library/sonus.json")!

    static var specExamples: URL {
        // <repo>/ios/SonusCore/Tests/SonusCoreTests/ManifestTests.swift → <repo>/spec/examples
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("spec/examples")
    }

    static func fixtures(_ folder: String) throws -> [URL] {
        let directory = specExamples.appendingPathComponent(folder)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!files.isEmpty, "No fixtures found in \(directory.path)")
        return files
    }

    static func load(_ file: URL) throws -> SonusManifest {
        try SonusManifest.decode(from: Data(contentsOf: file))
    }

    @Test("Every valid spec example decodes with no issues")
    func validExamples() throws {
        for file in try Self.fixtures("manifest") {
            let manifest = try Self.load(file)
            let issues = ManifestValidator.issues(in: manifest, manifestURL: Self.manifestURL)
            #expect(issues.isEmpty, "\(file.lastPathComponent): \(issues)")
        }
    }

    @Test("Every invalid spec example is rejected")
    func invalidExamples() throws {
        for file in try Self.fixtures("manifest-invalid") {
            let data = try Data(contentsOf: file)
            guard let manifest = try? SonusManifest.decode(from: data) else {
                continue // Rejected at decode time, e.g. a missing required field.
            }
            let issues = ManifestValidator.issues(in: manifest, manifestURL: Self.manifestURL)
            #expect(!issues.isEmpty, "\(file.lastPathComponent) should be rejected")
        }
    }

    @Test("The full example decodes every field")
    func fullExampleFields() throws {
        let manifest = try Self.load(Self.specExamples.appendingPathComponent("manifest/full.json"))
        #expect(manifest.sonus == "1.0")
        #expect(manifest.library.name == "Living-room NAS")
        #expect(manifest.library.updatedAt != nil)
        #expect(manifest.baseURL == URL(string: "https://music.example.com/library/"))
        #expect(manifest.tracks.count == 2)
        let first = try #require(manifest.tracks.first)
        #expect(first.duration == 214.6)
        #expect(first.size == 8_583_680)
        #expect(first.albumId == "al-night-drive")
        #expect(manifest.playlists.first?.trackIds == ["tr-night-drive-02", "tr-night-drive-01"])
    }

    @Test("Unknown fields are ignored for forward compatibility")
    func unknownFieldsIgnored() throws {
        let json = """
        {"sonus": "1.7", "futureTopLevel": true,
         "library": {"id": "lib", "name": "Lib", "futureField": 1},
         "tracks": [{"id": "t", "title": "T", "url": "t.mp3", "lyrics": "la"}]}
        """
        let manifest = try SonusManifest.decode(from: Data(json.utf8))
        #expect(ManifestValidator.issues(in: manifest, manifestURL: Self.manifestURL).isEmpty)
    }

    @Test("Dates accept fractional seconds")
    func fractionalSecondDates() throws {
        let json = """
        {"sonus": "1.0", "library": {"id": "lib", "name": "Lib", "updatedAt": "2026-10-11T18:30:00.250Z"}, "tracks": []}
        """
        let manifest = try SonusManifest.decode(from: Data(json.utf8))
        #expect(manifest.library.updatedAt != nil)
    }

    @Test("Version support mirrors the schema pattern", arguments: [
        ("1.0", true), ("1.12", true), ("2.0", false), ("1", false), ("01.0", false), ("1.x", false), ("1.", false)
    ])
    func versionSupport(version: String, supported: Bool) {
        #expect(ManifestValidator.isSupported(version: version) == supported)
    }

    @Test("IDs follow the spec's character rules", arguments: [
        ("tr-01", true), ("mbid:5b11f4ce.a62d_471e", true), ("has space", false), ("", false), ("ünïcode", false)
    ])
    func idRules(id: String, valid: Bool) {
        #expect(ManifestValidator.isValidID(id) == valid)
    }
}

@Suite("URL resolution and network policy")
struct URLTests {
    @Test("Relative URLs resolve like a browser", arguments: [
        ("albums/a/01.mp3", "https://music.example.com/library/albums/a/01.mp3"),
        ("/other/01.mp3", "https://music.example.com/other/01.mp3"),
        ("https://cdn.example.com/01.flac", "https://cdn.example.com/01.flac")
    ])
    func relativeResolution(reference: String, expected: String) throws {
        let manifest = SonusManifest(library: .init(id: "lib", name: "Lib"))
        let resolver = ManifestURLResolver(manifest: manifest, manifestURL: ManifestTests.manifestURL)
        #expect(resolver.resolve(reference)?.absoluteString == expected)
    }

    @Test("baseUrl overrides the manifest location")
    func baseURLOverride() {
        let manifest = SonusManifest(library: .init(id: "lib", name: "Lib"), baseURL: URL(string: "https://cdn.example.com/m/"))
        let resolver = ManifestURLResolver(manifest: manifest, manifestURL: ManifestTests.manifestURL)
        #expect(resolver.resolve("01.mp3")?.absoluteString == "https://cdn.example.com/m/01.mp3")
    }

    @Test("https everywhere, http only on the local network", arguments: [
        ("https://music.example.com/a.mp3", true),
        ("http://192.168.1.20/a.mp3", true),
        ("http://10.0.0.5:4533/a.mp3", true),
        ("http://172.16.4.2/a.mp3", true),
        ("http://nas.local/a.mp3", true),
        ("http://localhost:8080/a.mp3", true),
        ("http://[::1]/a.mp3", true),
        ("http://music.example.com/a.mp3", false),
        ("http://172.32.0.1/a.mp3", false),
        ("http://8.8.8.8/a.mp3", false),
        ("ftp://nas.local/a.mp3", false),
        ("file:///etc/passwd", false)
    ])
    func networkPolicy(url: String, allowed: Bool) throws {
        let parsed = try #require(URL(string: url))
        #expect(NetworkPolicy.allows(parsed) == allowed)
    }

    @Test("An insecure track URL is reported")
    func insecureTrackURL() {
        var manifest = SonusManifest(library: .init(id: "lib", name: "Lib"))
        manifest.tracks = [.init(id: "t", title: "T", url: "http://music.example.com/t.mp3")]
        let issues = ManifestValidator.issues(in: manifest, manifestURL: ManifestTests.manifestURL)
        #expect(issues.contains { if case .insecureURL = $0 { true } else { false } })
    }
}
