import Foundation

/// A user name and password for an OpenSubsonic server (Navidrome, Gonic, Ampache, ...).
///
/// Stored as one Keychain item (``encodedSecret``) and nowhere else. The password never goes
/// over the network: requests carry a salted MD5 token instead (Subsonic API 1.13+).
public struct OpenSubsonicCredentials: Codable, Hashable, Sendable, CustomStringConvertible {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// The Keychain form: a small JSON object.
    public var encodedSecret: String {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Reads ``encodedSecret``; nil for anything else.
    public init?(secret: String) {
        guard let decoded = try? JSONDecoder().decode(Self.self, from: Data(secret.utf8)),
              !decoded.username.isEmpty else {
            return nil
        }
        self = decoded
    }

    public var description: String {
        "OpenSubsonicCredentials(username: \(username), password: <redacted>)"
    }

    /// The `u`, `t` and `s` parameters for one salt.
    public func tokenParameters(salt: String) -> [String: String] {
        ["u": username, "t": MD5.hex(password + salt), "s": salt]
    }

    /// The authorization for requests to `serverURL`'s host, with a fresh random salt.
    public func authorization(for serverURL: URL, salt: String = OpenSubsonicCredentials.randomSalt()) -> RequestAuthorization? {
        guard let host = serverURL.host?.lowercased() else { return nil }
        return .query(tokenParameters(salt: salt), hosts: [host])
    }

    public static func randomSalt(length: Int = 16) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] })
    }
}

/// Builds OpenSubsonic API URLs. URLs never contain credentials: ``RequestAuthorization`` adds
/// them to each request, so stream URLs can be stored and synced safely.
public struct OpenSubsonicEndpoints: Hashable, Sendable {
    /// The REST API version Sonus speaks. 1.16.1 is the base OpenSubsonic extends.
    public static let apiVersion = "1.16.1"
    public static let clientName = "Sonus"

    /// The server's base URL as the person typed it, e.g. `https://music.example.com` or
    /// `http://192.168.1.20:4533/navidrome`.
    public let serverURL: URL

    public init(serverURL: URL) {
        self.serverURL = serverURL
    }

    /// `rest/<method>` with the protocol parameters and `parameters`.
    public func url(_ method: String, _ parameters: [String: String] = [:]) -> URL? {
        let base = serverURL.appendingPathComponent("rest").appendingPathComponent(method)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: true) else { return nil }
        var all = parameters
        all["v"] = Self.apiVersion
        all["c"] = Self.clientName
        components.percentEncodedQueryItems = all.keys.sorted().map {
            URLQueryItem(name: $0, value: all[$0]?.strictlyPercentEncoded)
        }
        return components.url
    }

    public var ping: URL? { url("ping", ["f": "json"]) }

    public func albumList(offset: Int, size: Int) -> URL? {
        url("getAlbumList2", ["f": "json", "type": "alphabeticalByName", "size": String(size), "offset": String(offset)])
    }

    public func album(id: String) -> URL? {
        url("getAlbum", ["f": "json", "id": id])
    }

    /// The original file (`format=raw`), so byte ranges and the file type stay exact.
    public func stream(id: String) -> URL? {
        url("stream", ["id": id, "format": "raw"])
    }

    public func coverArt(id: String, size: Int = 600) -> URL? {
        url("getCoverArt", ["id": id, "size": String(size)])
    }

    /// Normalises what a person typed: adds `https://` when there's no scheme (or `http://` for a
    /// local address), and drops a trailing `/rest` or slash.
    public static func serverURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.contains("://") {
            let host = text.split(separator: "/").first.map { String($0.split(separator: ":").first ?? $0[...]) } ?? text
            text = (NetworkPolicy.isLocal(host: host) ? "http://" : "https://") + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        if text.lowercased().hasSuffix("/rest") {
            text.removeLast(5)
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

/// A failure the server reported in its `subsonic-response`.
public struct OpenSubsonicError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: Int
    public let message: String?

    public init(code: Int, message: String?) {
        self.code = code
        self.message = message
    }

    public var description: String {
        switch code {
        case 40:
            "Wrong username or password."
        case 41, 42:
            "This server doesn't accept Sonus's secure sign-in (token authentication). "
                + "Servers that check passwords with LDAP often can't; ask the server's admin."
        case 20, 30:
            "This server's Subsonic API is too old for Sonus. Update the server and try again."
        case 50:
            "This account isn't allowed to do that on the server."
        case 70:
            "The server couldn't find that item."
        default:
            message.map { "The server said: \($0)" } ?? "The server reported error \(code)."
        }
    }
}

// MARK: - Responses

/// The `subsonic-response` envelope with an optional payload.
struct OpenSubsonicEnvelope<Payload: OpenSubsonicPayload>: Decodable {
    let response: OpenSubsonicResponse<Payload>

    enum CodingKeys: String, CodingKey {
        case response = "subsonic-response"
    }
}

struct OpenSubsonicResponse<Payload: OpenSubsonicPayload>: Decodable {
    let status: String
    let error: ErrorBody?
    let type: String?
    let payload: Payload?

    struct ErrorBody: Decodable {
        let code: LenientInt
        let message: String?
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        status = try container.decode(String.self, forKey: AnyKey(stringValue: "status"))
        error = try? container.decodeIfPresent(ErrorBody.self, forKey: AnyKey(stringValue: "error"))
        type = try? container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "type"))
        // Every payload sits under one key named after it (`albumList2`, `album`, ...).
        let payloadKey = AnyKey(stringValue: Payload.key)
        if container.contains(payloadKey) {
            payload = try container.decode(Payload.self, forKey: payloadKey)
        } else {
            payload = nil
        }
    }

    /// The payload, or the server's error.
    func unwrap() throws -> Payload? {
        guard status == "ok" else {
            throw OpenSubsonicError(code: error?.code.value ?? 0, message: error?.message)
        }
        return payload
    }
}

protocol OpenSubsonicPayload: Decodable, Sendable {
    static var key: String { get }
}

struct OpenSubsonicNothing: OpenSubsonicPayload {
    static let key = "_none"
}

struct OpenSubsonicAlbumList: OpenSubsonicPayload {
    static let key = "albumList2"
    let album: OneOrMany<OpenSubsonicAlbum>?
}

struct OpenSubsonicAlbumDetail: OpenSubsonicPayload {
    static let key = "album"
    let id: LenientString
    let name: String?
    let artist: String?
    let coverArt: LenientString?
    let song: OneOrMany<OpenSubsonicSong>?
}

struct OpenSubsonicAlbum: Decodable, Sendable {
    let id: LenientString
    let name: String?
}

struct OpenSubsonicSong: Decodable, Sendable {
    let id: LenientString
    let title: String?
    let artist: String?
    let album: String?
    let duration: LenientInt?
    let size: LenientInt?
    let contentType: String?
    let suffix: String?
    let coverArt: LenientString?
    let isVideo: Bool?
    let path: String?
}

/// Old Subsonic servers encode a one-element array as a bare object.
struct OneOrMany<Element: Decodable & Sendable>: Decodable, Sendable {
    let values: [Element]

    init(from decoder: any Decoder) throws {
        if let array = try? [Element](from: decoder) {
            values = array
        } else {
            values = [try Element(from: decoder)]
        }
    }
}

/// Some servers send IDs as numbers.
struct LenientString: Decodable, Hashable, Sendable {
    let value: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let number = try? container.decode(Int64.self) {
            value = String(number)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a string or number")
        }
    }
}

/// Some servers send numbers as strings or with a fraction.
struct LenientInt: Decodable, Hashable, Sendable {
    let value: Int

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self), double.isFinite {
            value = Int(double)
        } else if let string = try? container.decode(String.self), let int = Int(string) {
            value = int
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a number")
        }
    }
}
