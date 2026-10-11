import Foundation

/// A rule in the Sonus Manifest spec that a manifest breaks.
public enum ManifestIssue: Equatable, Sendable, CustomStringConvertible {
    case unsupportedVersion(String)
    case invalidID(collection: String, id: String)
    case duplicateID(collection: String, id: String)
    case unknownReference(owner: String, field: String, id: String)
    case invalidURL(owner: String, value: String)
    case insecureURL(owner: String, url: URL)

    public var description: String {
        switch self {
        case .unsupportedVersion(let version):
            "Unsupported spec version \"\(version)\"; this app reads 1.x manifests."
        case .invalidID(let collection, let id):
            "\(collection) id \"\(id)\" may only contain letters, digits, '.', '_', ':' and '-'."
        case .duplicateID(let collection, let id):
            "Duplicate \(collection) id \"\(id)\"."
        case .unknownReference(let owner, let field, let id):
            "\(owner) \(field) references unknown id \"\(id)\"."
        case .invalidURL(let owner, let value):
            "\(owner) has an invalid URL \"\(value)\"."
        case .insecureURL(let owner, let url):
            "\(owner) uses \(url.absoluteString); remote hosts must use https."
        }
    }
}

/// Checks the rules from "Rules the schema can't check" in the Sonus Manifest spec.
public enum ManifestValidator {
    static let supportedMajorVersion = 1

    /// Returns every issue found, or an empty array for a valid manifest.
    /// - Parameter manifestURL: where the manifest was fetched from; relative URLs resolve
    ///   against it unless the manifest sets `baseUrl`.
    public static func issues(in manifest: SonusManifest, manifestURL: URL) -> [ManifestIssue] {
        var issues: [ManifestIssue] = []
        if !isSupported(version: manifest.sonus) {
            issues.append(.unsupportedVersion(manifest.sonus))
        }
        checkIDsAndReferences(in: manifest, into: &issues)
        checkURLs(in: manifest, manifestURL: manifestURL, into: &issues)
        return issues
    }

    private static func checkIDsAndReferences(in manifest: SonusManifest, into issues: inout [ManifestIssue]) {
        checkID(manifest.library.id, collection: "library", into: &issues)
        let artistIDs = uniqueIDs(manifest.artists.map(\.id), collection: "artists", into: &issues)
        let albumIDs = uniqueIDs(manifest.albums.map(\.id), collection: "albums", into: &issues)
        let trackIDs = uniqueIDs(manifest.tracks.map(\.id), collection: "tracks", into: &issues)
        _ = uniqueIDs(manifest.playlists.map(\.id), collection: "playlists", into: &issues)

        func expect(_ id: String?, in known: Set<String>, owner: String, field: String) {
            if let id, !known.contains(id) {
                issues.append(.unknownReference(owner: owner, field: field, id: id))
            }
        }
        for album in manifest.albums {
            expect(album.artistId, in: artistIDs, owner: "album \"\(album.id)\"", field: "artistId")
        }
        for track in manifest.tracks {
            expect(track.artistId, in: artistIDs, owner: "track \"\(track.id)\"", field: "artistId")
            expect(track.albumId, in: albumIDs, owner: "track \"\(track.id)\"", field: "albumId")
        }
        for playlist in manifest.playlists {
            for trackID in playlist.trackIds {
                expect(trackID, in: trackIDs, owner: "playlist \"\(playlist.id)\"", field: "trackIds")
            }
        }
    }

    private static func checkURLs(in manifest: SonusManifest, manifestURL: URL, into issues: inout [ManifestIssue]) {
        let resolver = ManifestURLResolver(manifest: manifest, manifestURL: manifestURL)
        func checkURL(_ reference: String?, owner: String) {
            guard let reference else { return }
            guard let url = resolver.resolve(reference) else {
                issues.append(.invalidURL(owner: owner, value: reference))
                return
            }
            if !NetworkPolicy.allows(url) {
                issues.append(.insecureURL(owner: owner, url: url))
            }
        }
        for artist in manifest.artists {
            checkURL(artist.artwork, owner: "artist \"\(artist.id)\"")
        }
        for album in manifest.albums {
            checkURL(album.artwork, owner: "album \"\(album.id)\"")
        }
        for track in manifest.tracks {
            checkURL(track.url, owner: "track \"\(track.id)\"")
            checkURL(track.artwork, owner: "track \"\(track.id)\"")
        }
        for playlist in manifest.playlists {
            checkURL(playlist.artwork, owner: "playlist \"\(playlist.id)\"")
        }
    }

    static func isSupported(version: String) -> Bool {
        // Mirrors the schema pattern ^1\.[0-9]+$
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "\(supportedMajorVersion)", !parts[1].isEmpty else {
            return false
        }
        return parts[1].allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func isValidID(_ id: String) -> Bool {
        guard (1...256).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._:-".unicodeScalars.contains(scalar))
        }
    }

    private static func checkID(_ id: String, collection: String, into issues: inout [ManifestIssue]) {
        if !isValidID(id) {
            issues.append(.invalidID(collection: collection, id: id))
        }
    }

    private static func uniqueIDs(_ ids: [String], collection: String, into issues: inout [ManifestIssue]) -> Set<String> {
        var seen = Set<String>()
        for id in ids {
            checkID(id, collection: collection, into: &issues)
            if !seen.insert(id).inserted {
                issues.append(.duplicateID(collection: collection, id: id))
            }
        }
        return seen
    }
}

/// Resolves the relative URL references in a manifest, the same way a browser would.
public struct ManifestURLResolver: Sendable {
    public let base: URL

    public init(manifest: SonusManifest, manifestURL: URL) {
        base = manifest.baseURL ?? manifestURL
    }

    public func resolve(_ reference: String) -> URL? {
        guard !reference.isEmpty, let url = URL(string: reference, relativeTo: base)?.absoluteURL,
              url.scheme != nil, url.host != nil else {
            return nil
        }
        return url
    }
}

/// Which URLs Sonus will fetch: `https` anywhere, plain `http` only on the local network.
public enum NetworkPolicy {
    public static func allows(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return url.host != nil
        case "http":
            guard let host = url.host else { return false }
            return isLocal(host: host)
        default:
            return false
        }
    }

    /// `localhost`, mDNS `.local` names, and private/link-local IPv4 and IPv6 addresses.
    public static func isLocal(host rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }
        if let octets = ipv4Octets(host) {
            switch (octets[0], octets[1]) {
            case (10, _), (127, _), (192, 168), (169, 254):
                return true
            case (172, let second):
                return (16...31).contains(second)
            default:
                return false
            }
        }
        if host.contains(":") {
            return host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:")
        }
        return false
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part), (0...255).contains(value) else {
                return nil
            }
            return value
        }
        return octets.count == 4 ? octets : nil
    }
}
