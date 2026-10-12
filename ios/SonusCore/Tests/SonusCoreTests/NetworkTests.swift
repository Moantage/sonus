import Foundation
import Testing
@testable import SonusCore

/// Byte-range reads, header handling and redirects against a real local HTTP server.
@Suite("Ranged HTTP client")
struct RangedHTTPClientTests {
    static let payload = Data((0..<50_000).map { UInt8($0 % 251) })

    @Test("Content-Range headers parse", arguments: [
        ("bytes 0-1/50000", "0-1 of 50000"),
        ("bytes 100-199/*", "100-199 of ?"),
        ("bytes 5-4/10", nil),
        ("bytes 0-10/10", nil),
        ("items 0-1/2", nil)
    ] as [(String, String?)])
    func contentRange(header: String, expected: String?) {
        let parsed = ContentRange(headerValue: header)
        #expect(parsed.map { "\($0.first)-\($0.last) of \($0.totalLength.map(String.init) ?? "?")" } == expected)
    }

    @Test("Range header values")
    func rangeHeaders() {
        #expect(ByteRange(lowerBound: 0, upperBound: 1).headerValue == "bytes=0-1")
        #expect(ByteRange(lowerBound: 4096).headerValue == "bytes=4096-")
        #expect(ByteRange(offset: 10, length: 5)?.upperBound == 14)
        #expect(ByteRange(offset: 10, length: 0) == nil)
    }

    @Test("A range request returns exactly those bytes and the full length")
    func rangedRead() async throws {
        let server = try MockHTTPServer { .file(Self.payload, for: $0) }
        defer { server.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let range = try #require(ByteRange(offset: 1_000, length: 2_048))
        let (data, head) = try await client.data(server.baseURL.appendingPathComponent("track.mp3"), range: range)
        #expect(data == Self.payload.subdata(in: 1_000..<3_048))
        #expect(head.statusCode == 206)
        #expect(head.totalLength == Int64(Self.payload.count))
        #expect(head.servesByteRanges)

        let request = try #require(server.requests.last)
        #expect(request.headers["range"] == "bytes=1000-3047")
        #expect(request.headers["accept-encoding"] == "identity")
    }

    @Test("An open-ended range reads to the end")
    func openEnded() async throws {
        let server = try MockHTTPServer { .file(Self.payload, for: $0) }
        defer { server.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let (data, _) = try await client.data(server.baseURL.appendingPathComponent("t.mp3"), range: ByteRange(lowerBound: 49_000))
        #expect(data == Self.payload.subdata(in: 49_000..<50_000))
    }

    @Test("A server that ignores Range still yields the requested bytes")
    func serverIgnoresRange() async throws {
        let server = try MockHTTPServer { _ in MockHTTPServer.Response(status: 200, body: Self.payload) }
        defer { server.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let range = try #require(ByteRange(offset: 300, length: 100))
        let (data, head) = try await client.data(server.baseURL.appendingPathComponent("t.mp3"), range: range)
        #expect(data == Self.payload.subdata(in: 300..<400))
        #expect(!head.servesByteRanges)
    }

    @Test("The secret header reaches an allowed host and no other")
    func authorizationHosts() async throws {
        let server = try MockHTTPServer { request in
            request.headers["authorization"] == "Bearer s3cret" ? .file(Self.payload, for: request) : .init(status: 401)
        }
        defer { server.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let allowed = RequestAuthorization.bearer("s3cret", hosts: ["localhost"])
        let range = ByteRange(lowerBound: 0, upperBound: 9)
        let (data, _) = try await client.data(server.baseURL.appendingPathComponent("private.mp3"), range: range, authorization: allowed)
        #expect(data.count == 10)

        let elsewhere = RequestAuthorization.bearer("s3cret", hosts: ["music.example.com"])
        await #expect(throws: HTTPClientError.self) {
            try await client.data(server.baseURL.appendingPathComponent("private.mp3"), range: range, authorization: elsewhere)
        }
        #expect(server.requests.last?.headers["authorization"] == nil)
    }

    @Test("A redirect to another host drops the secret header but keeps the range")
    func redirectDropsSecret() async throws {
        let box = PortBox()
        let server = try MockHTTPServer { request in
            if request.path == "/redirect" {
                return .init(status: 302, headers: ["Location": "http://127.0.0.1:\(box.port)/track.mp3"])
            }
            return .file(Self.payload, for: request)
        }
        box.port = server.port
        defer { server.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        let authorization = RequestAuthorization.bearer("s3cret", hosts: ["localhost"])
        let range = ByteRange(lowerBound: 10, upperBound: 19)
        let url = server.baseURL.appendingPathComponent("redirect")
        let (data, head) = try await client.data(url, range: range, authorization: authorization)
        #expect(data == Self.payload.subdata(in: 10..<20))
        #expect(head.url?.host == "127.0.0.1")

        let requests = server.requests
        #expect(requests.count == 2)
        #expect(requests.first?.headers["authorization"] == "Bearer s3cret")
        #expect(requests.last?.headers["authorization"] == nil)
        #expect(requests.last?.headers["range"] == "bytes=10-19")
    }

    @Test("HTTP errors carry their status and headers")
    func statusErrors() async throws {
        let server = try MockHTTPServer { _ in .init(status: 403, headers: ["X-RateLimit-Remaining": "0", "Retry-After": "60"]) }
        defer { server.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }

        do {
            _ = try await client.data(server.baseURL.appendingPathComponent("x"))
            Issue.record("Expected an error")
        } catch let error as HTTPClientError {
            #expect(error.statusCode == 403)
            if case .status(let head) = error {
                #expect(GitHubAPIError.classify(statusCode: head.statusCode, headers: head.headers, hasToken: true)
                    == .rateLimited(retryAfter: 60))
            }
        }
    }

    @Test("Insecure URLs are refused before any request")
    func blocked() async throws {
        let client = StreamingHTTPClient()
        defer { client.invalidate() }
        let url = try #require(URL(string: "http://music.example.com/a.mp3"))
        await #expect(throws: HTTPClientError.blockedURL(url)) {
            try await client.data(url)
        }
    }

    @Test("Reads over the size limit fail")
    func sizeLimit() async throws {
        let server = try MockHTTPServer { .file(Self.payload, for: $0) }
        defer { server.stop() }
        let client = StreamingHTTPClient()
        defer { client.invalidate() }
        await #expect(throws: HTTPClientError.tooLarge(limit: 1_000)) {
            try await client.data(server.baseURL.appendingPathComponent("t.mp3"), maxBytes: 1_000)
        }
    }
}

final class PortBox: @unchecked Sendable {
    var port: UInt16 = 0
}
