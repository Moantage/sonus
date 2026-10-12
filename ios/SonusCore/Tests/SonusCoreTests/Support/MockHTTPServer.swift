import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A tiny HTTP/1.1 server on 127.0.0.1 for tests. It records every request and answers with a
/// handler, one connection at a time, closing each connection after the response.
final class MockHTTPServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        /// Path and query exactly as sent, still percent-encoded.
        let target: String
        /// Lowercased header names.
        let headers: [String: String]

        var path: String {
            String(target.split(separator: "?", maxSplits: 1).first ?? "")
        }
    }

    struct Response: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()

        static func json(_ text: String, status: Int = 200) -> Response {
            Response(status: status, headers: ["Content-Type": "application/json"], body: Data(text.utf8))
        }

        static func notFound() -> Response {
            Response(status: 404, body: Data("not found".utf8))
        }

        /// Serves `data` with byte-range support.
        static func file(_ data: Data, for request: Request, contentType: String = "application/octet-stream") -> Response {
            var headers = ["Content-Type": contentType, "Accept-Ranges": "bytes"]
            guard let rangeHeader = request.headers["range"] else {
                return Response(status: 200, headers: headers, body: data)
            }
            guard let (first, last) = parseRange(rangeHeader, size: data.count) else {
                headers["Content-Range"] = "bytes */\(data.count)"
                return Response(status: 416, headers: headers)
            }
            headers["Content-Range"] = "bytes \(first)-\(last)/\(data.count)"
            return Response(status: 206, headers: headers, body: data.subdata(in: first..<(last + 1)))
        }

        private static func parseRange(_ header: String, size: Int) -> (Int, Int)? {
            guard header.hasPrefix("bytes=") else { return nil }
            let bounds = header.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
            guard bounds.count == 2, let first = Int(bounds[0]), first < size else { return nil }
            let last = bounds[1].isEmpty ? size - 1 : min(Int(bounds[1]) ?? (size - 1), size - 1)
            return last >= first ? (first, last) : nil
        }
    }

    typealias Handler = @Sendable (Request) -> Response

    let port: UInt16
    private let listener: Int32
    private let handler: Handler
    private let lock = NSLock()
    private var recorded: [Request] = []

    var requests: [Request] {
        lock.withLock { recorded }
    }

    /// `http://localhost:<port>`.
    var baseURL: URL {
        URL(string: "http://localhost:\(port)") ?? URL(fileURLWithPath: "/")
    }

    /// `http://127.0.0.1:<port>`: the same server under a different host name.
    var ipBaseURL: URL {
        URL(string: "http://127.0.0.1:\(port)") ?? URL(fileURLWithPath: "/")
    }

    init(handler: @escaping Handler) throws {
        self.handler = handler
        #if canImport(Glibc)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif
        let descriptor = socket(AF_INET, socketType, 0)
        guard descriptor >= 0 else { throw MockServerError.socket }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 16) == 0 else {
            close(descriptor)
            throw MockServerError.bind
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        listener = descriptor
        port = UInt16(bigEndian: address.sin_port)

        let thread = Thread { [self] in acceptLoop() }
        thread.start()
    }

    func stop() {
        shutdown(listener, Int32(SHUT_RDWR))
        close(listener)
    }

    private func acceptLoop() {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { return }
            #if canImport(Darwin)
            var noSignal: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            #endif
            serve(connection)
            close(connection)
        }
    }

    private func serve(_ connection: Int32) {
        guard let request = readRequest(from: connection) else { return }
        lock.withLock { recorded.append(request) }
        var response = handler(request)
        response.headers["Content-Length"] = String(response.body.count)
        response.headers["Connection"] = "close"
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        for (field, value) in response.headers {
            head += "\(field): \(value)\r\n"
        }
        head += "\r\n"
        var bytes = Data(head.utf8)
        if request.method != "HEAD" {
            bytes.append(response.body)
        }
        write(bytes, to: connection)
    }

    private func readRequest(from connection: Int32) -> Request? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        let terminator = Data("\r\n\r\n".utf8)
        while buffer.range(of: terminator) == nil {
            let count = recv(connection, &chunk, chunk.count, 0)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<count])
            if buffer.count > 64 * 1024 { return nil }
        }
        guard let headerEnd = buffer.range(of: terminator),
              let text = String(data: buffer.subdata(in: 0..<headerEnd.lowerBound), encoding: .utf8) else {
            return nil
        }
        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return Request(method: String(requestLine[0]), target: String(requestLine[1]), headers: headers)
    }

    private func write(_ data: Data, to connection: Int32) {
        #if canImport(Glibc)
        let flags = Int32(MSG_NOSIGNAL)
        #else
        let flags: Int32 = 0
        #endif
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let sent = send(connection, base + offset, data.count - offset, flags)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }

    private static func reason(_ status: Int) -> String {
        [200: "OK", 206: "Partial Content", 302: "Found", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
         416: "Range Not Satisfiable", 429: "Too Many Requests"][status] ?? "Status"
    }
}

enum MockServerError: Error {
    case socket
    case bind
}
