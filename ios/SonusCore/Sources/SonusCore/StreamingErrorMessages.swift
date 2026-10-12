import Foundation

/// One error in a chain of underlying errors, reduced to plain values.
public struct ErrorLink: Equatable, Sendable {
    public var domain: String
    public var code: Int
    /// A message to show as is, for errors Sonus created itself.
    public var message: String?

    public init(domain: String, code: Int, message: String? = nil) {
        self.domain = domain
        self.code = code
        self.message = message
    }
}

/// Turns playback and download failures into messages a person can act on.
public enum StreamingErrorMessages {
    /// Error domain for failures Sonus reports itself; their message is shown as is.
    public static let sonusDomain = "com.novoralabs.sonus"
    public static let urlDomain = "NSURLErrorDomain"
    public static let avFoundationDomain = "AVFoundationErrorDomain"
    public static let coreMediaDomain = "CoreMediaErrorDomain"

    public static let generic = "This track could not be played."
    public static let offline = "You're offline. Connect to the internet, or download songs to play them offline."
    public static let unreachable = "Couldn't reach the music server. Check that it's running and that you're on the same network."
    public static let timedOut = "The music server took too long to respond."
    public static let insecure = "Couldn't make a secure connection to the music server."
    public static let blocked = "This server isn't allowed: remote servers must use https."
    public static let noRangeSupport = "The server can't stream this song because it doesn't support HTTP range requests."
    public static let notFound = "The song wasn't found on the server."
    public static let denied = "The server refused access to this song."
    public static let unsupportedFormat = "This file format isn't supported."

    private static let urlMessages: [Int: String] = [
        -1009: offline, -1018: offline, -1020: offline,
        -1005: unreachable, -1003: unreachable, -1004: unreachable, -1006: unreachable,
        -1001: timedOut,
        -1200: insecure, -1201: insecure, -1202: insecure, -1203: insecure, -1204: insecure, -1205: insecure, -1206: insecure,
        -1022: blocked,
        -1100: notFound, -1012: denied, -1013: denied
    ]

    private static let avFoundationMessages: [Int: String] = [
        -11850: noRangeSupport,
        -11828: unsupportedFormat, -11829: unsupportedFormat, -11821: unsupportedFormat, -11833: unsupportedFormat
    ]

    private static let coreMediaMessages: [Int: String] = [
        -12938: notFound, -12660: denied
    ]

    /// The message for a network failure code (`NSURLErrorDomain`), if it has a specific one.
    public static func transportMessage(code: Int) -> String? {
        urlMessages[code]
    }

    /// The most specific message in an error chain (outermost first), or ``generic``.
    public static func message(for chain: [ErrorLink]) -> String {
        for link in chain {
            if let message = message(for: link) {
                return message
            }
        }
        return generic
    }

    private static func message(for link: ErrorLink) -> String? {
        switch link.domain {
        case sonusDomain:
            return link.message
        case urlDomain:
            return urlMessages[link.code]
        case avFoundationDomain:
            return avFoundationMessages[link.code]
        case coreMediaDomain:
            return coreMediaMessages[link.code]
        default:
            return nil
        }
    }
}
