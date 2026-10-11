import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An HTTP byte range, inclusive at both ends. A nil upper bound means "to the end".
public struct ByteRange: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let lowerBound: Int64
    public let upperBound: Int64?

    /// Negative bounds clamp to zero and an upper bound below the lower one clamps up to it.
    public init(lowerBound: Int64, upperBound: Int64? = nil) {
        let lower = max(0, lowerBound)
        self.lowerBound = lower
        self.upperBound = upperBound.map { max(lower, $0) }
    }

    /// `length` bytes starting at `offset`.
    public init?(offset: Int64, length: Int64) {
        guard length > 0 else { return nil }
        self.init(lowerBound: offset, upperBound: offset + length - 1)
    }

    /// Number of bytes, when bounded.
    public var length: Int64? {
        upperBound.map { $0 - lowerBound + 1 }
    }

    /// The `Range` header value, e.g. `bytes=0-1023` or `bytes=4096-`.
    public var headerValue: String {
        "bytes=\(lowerBound)-\(upperBound.map(String.init) ?? "")"
    }

    public var description: String { headerValue }
}

/// The parts of an HTTP response a ranged reader needs. Header names are lowercased.
public struct HTTPResponseHead: Equatable, Sendable {
    /// The final URL, after redirects.
    public var url: URL?
    public var statusCode: Int
    public var headers: [String: String]

    public init(url: URL?, statusCode: Int, headers: [String: String]) {
        self.url = url
        self.statusCode = statusCode
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    public init(_ response: HTTPURLResponse) {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key.lowercased()] = value
            }
        }
        self.init(url: response.url, statusCode: response.statusCode, headers: headers)
    }

    public func value(for field: String) -> String? {
        headers[field.lowercased()]
    }

    /// MIME type without parameters, e.g. `audio/mpeg`.
    public var mimeType: String? {
        value(for: "content-type")?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    public var contentLength: Int64? {
        value(for: "content-length").flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// The `Content-Range` of a 206 response.
    public var contentRange: ContentRange? {
        value(for: "content-range").flatMap(ContentRange.init(headerValue:))
    }

    /// Size of the whole resource: from `Content-Range` on a 206, else `Content-Length` on a 200.
    public var totalLength: Int64? {
        if statusCode == 206 {
            return contentRange?.totalLength
        }
        return statusCode == 200 ? contentLength : nil
    }

    /// True when the server answered a range request with a partial response.
    public var servesByteRanges: Bool {
        statusCode == 206 || value(for: "accept-ranges")?.lowercased().contains("bytes") == true
    }
}

/// A parsed `Content-Range: bytes <first>-<last>/<total|*>` header.
public struct ContentRange: Equatable, Sendable {
    public let first: Int64
    public let last: Int64
    public let totalLength: Int64?

    public init?(headerValue: String) {
        let trimmed = headerValue.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes ") else { return nil }
        let spec = trimmed.dropFirst("bytes ".count)
        let parts = spec.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let bounds = parts[0].split(separator: "-", maxSplits: 1)
        guard bounds.count == 2, let first = Int64(bounds[0]), let last = Int64(bounds[1]), first <= last else {
            return nil
        }
        let total = parts[1] == "*" ? nil : Int64(parts[1])
        if parts[1] != "*" && total == nil { return nil }
        if let total, last >= total { return nil }
        self.first = first
        self.last = last
        self.totalLength = total
    }
}

/// Builds requests for ranged, optionally authorized reads.
public enum RangedRequest {
    public static func make(
        url: URL,
        range: ByteRange?,
        authorization: RequestAuthorization?,
        headers: [String: String] = [:]
    ) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        for (field, value) in carriedHeaders(range: range, extra: headers) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        authorization?.authorize(&request)
        return request
    }

    /// Headers that must survive redirects: the range, no compression (byte offsets must refer
    /// to the file itself) and the caller's own.
    public static func carriedHeaders(range: ByteRange?, extra: [String: String]) -> [String: String] {
        var headers = extra
        headers["Accept-Encoding"] = "identity"
        if let range {
            headers["Range"] = range.headerValue
        }
        return headers
    }
}
