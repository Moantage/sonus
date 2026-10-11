import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A secret header and the only hosts allowed to receive it.
///
/// Auth-agnostic: GitHub tokens use it today; Sonus Server bearer tokens and private buckets can
/// use it later. It is never persisted: build it from the Keychain when it's needed. Its
/// description redacts the secret, so printing it can't leak the token.
public struct RequestAuthorization: Hashable, Sendable, CustomStringConvertible {
    public let headerField: String
    private let headerValue: String
    /// Lowercase host names that may receive the header. Matched exactly: no subdomains.
    public let allowedHosts: Set<String>

    public init(headerField: String = "Authorization", headerValue: String, allowedHosts: Set<String>) {
        self.headerField = headerField
        self.headerValue = headerValue
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

    /// The header to add to a request for `url`; empty when the host isn't allowed.
    public func headers(for url: URL) -> [String: String] {
        applies(to: url) ? [headerField: headerValue] : [:]
    }

    /// Sets or removes the header on `request` according to its URL.
    public func authorize(_ request: inout URLRequest) {
        if let url = request.url, applies(to: url) {
            request.setValue(headerValue, forHTTPHeaderField: headerField)
        } else {
            request.setValue(nil, forHTTPHeaderField: headerField)
        }
    }

    public var description: String {
        "RequestAuthorization(\(headerField): <redacted>, hosts: \(allowedHosts.sorted()))"
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
