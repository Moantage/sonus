import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A secret (a header or query parameters) and the only hosts allowed to receive it.
///
/// Auth-agnostic: GitHub tokens and manifest bearer tokens use a header; OpenSubsonic servers use
/// query parameters (`u`, `t`, `s`). It is never persisted: build it from the Keychain when it's
/// needed. Its description redacts the secret, so printing it can't leak the token.
public struct RequestAuthorization: Hashable, Sendable, CustomStringConvertible {
    /// The header that carries the secret; empty when the secret travels as query parameters.
    public let headerField: String
    private let headerValue: String
    /// Query parameters that carry the secret, by name. Empty for header secrets.
    private let queryParameters: [String: String]
    /// Lowercase host names that may receive the secret. Matched exactly: no subdomains.
    public let allowedHosts: Set<String>

    public init(headerField: String = "Authorization", headerValue: String, allowedHosts: Set<String>) {
        self.headerField = headerField
        self.headerValue = headerValue
        self.queryParameters = [:]
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
    }

    private init(queryParameters: [String: String], allowedHosts: Set<String>) {
        self.headerField = ""
        self.headerValue = ""
        self.queryParameters = queryParameters
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
    }

    /// A bearer token for the given hosts.
    public static func bearer(_ token: String, hosts: Set<String>) -> RequestAuthorization {
        RequestAuthorization(headerValue: "Bearer \(token)", allowedHosts: hosts)
    }

    /// A GitHub token, sent only to the API, raw and LFS media hosts in `endpoints`.
    public static func gitHub(token: String, endpoints: GitHubEndpoints = .github) -> RequestAuthorization {
        RequestAuthorization(headerValue: "token \(token)", allowedHosts: endpoints.hosts)
    }

    /// Secret query parameters for the given hosts. Any parameter of the same name already in a
    /// URL is replaced, so authorizing twice (for example after a redirect) is harmless.
    public static func query(_ parameters: [String: String], hosts: Set<String>) -> RequestAuthorization {
        RequestAuthorization(queryParameters: parameters, allowedHosts: hosts)
    }

    /// Whether the secret travels as query parameters rather than a header.
    public var usesQueryParameters: Bool {
        !queryParameters.isEmpty
    }

    /// Whether `url` may receive the header: an exact host match over `https`, or plain `http`
    /// to a host that is both allowed and on the local network.
    public func applies(to url: URL) -> Bool {
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            return false
        }
        switch url.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            return NetworkPolicy.isLocal(host: host)
        default:
            return false
        }
    }

    /// The header to add to a request for `url`; empty when the host isn't allowed or the secret
    /// travels as query parameters.
    public func headers(for url: URL) -> [String: String] {
        applies(to: url) && !headerField.isEmpty ? [headerField: headerValue] : [:]
    }

    /// Adds the secret to `request` when its URL may receive it, and otherwise removes a secret
    /// header. Query secrets are never removed from a URL: Sonus only adds them to allowed hosts.
    public func authorize(_ request: inout URLRequest) {
        let allowed = request.url.map(applies(to:)) ?? false
        if !headerField.isEmpty {
            request.setValue(allowed ? headerValue : nil, forHTTPHeaderField: headerField)
        } else {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        if allowed, usesQueryParameters, let url = request.url {
            request.url = Self.url(url, adding: queryParameters)
        }
    }

    /// `url` with `parameters` set, replacing any of the same name, strictly percent-encoded so a
    /// `+` or `&` in a user name survives.
    static func url(_ url: URL, adding parameters: [String: String]) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        var items = (components.percentEncodedQueryItems ?? []).filter { parameters[$0.name] == nil }
        for name in parameters.keys.sorted() {
            items.append(URLQueryItem(name: name, value: parameters[name]?.strictlyPercentEncoded))
        }
        components.percentEncodedQueryItems = items
        return components.url ?? url
    }

    public var description: String {
        let carrier = usesQueryParameters ? "query \(queryParameters.keys.sorted())" : headerField
        return "RequestAuthorization(\(carrier): <redacted>, hosts: \(allowedHosts.sorted()))"
    }
}

/// What to do when a server redirects a request.
public enum RedirectPolicy {
    /// The request to follow, or nil to stop.
    ///
    /// Stops when the target breaks ``NetworkPolicy`` (for example an `https` → `http` downgrade
    /// to an internet host). Otherwise the secret header is re-applied for the new host, which
    /// removes it when the host isn't allowed, and `headers` (range, accept) carry over.
    public static func follow(
        _ proposed: URLRequest,
        authorization: RequestAuthorization?,
        headers: [String: String]
    ) -> URLRequest? {
        guard let url = proposed.url, NetworkPolicy.allows(url) else {
            return nil
        }
        var request = proposed
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let authorization {
            authorization.authorize(&request)
        } else {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

/// Custom URL schemes that route a stream through the app's own loader, which can add headers
/// that `AVPlayer` can't.
public enum AuthenticatedStreamURL {
    /// Stands in for `https`.
    public static let secureScheme = "sonus-auth"
    /// Stands in for plain `http` on the local network.
    public static let localScheme = "sonus-auth-http"

    public static func wrap(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = secureScheme
        case "http":
            components.scheme = localScheme
        default:
            return nil
        }
        return components.url
    }

    public static func unwrap(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        switch components.scheme?.lowercased() {
        case secureScheme:
            components.scheme = "https"
        case localScheme:
            components.scheme = "http"
        default:
            return nil
        }
        return components.url
    }

    public static func isWrapped(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == secureScheme || scheme == localScheme
    }
}

public extension URL {
    /// This URL without a `user:password@` part, for anything that leaves the device.
    var removingCredentials: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true),
              components.user != nil || components.password != nil else {
            return self
        }
        components.user = nil
        components.password = nil
        return components.url ?? self
    }
}

extension String {
    /// Percent-encodes everything except RFC 3986 unreserved characters.
    var strictlyPercentEncoded: String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
