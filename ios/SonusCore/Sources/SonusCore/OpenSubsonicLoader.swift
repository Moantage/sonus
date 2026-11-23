import Foundation

/// Lists an OpenSubsonic server (Navidrome, Gonic, Ampache, Airsonic-Advanced, ...) as a library.
///
/// 1. `ping` checks the address and the sign-in.
/// 2. `getAlbumList2` pages through every album, alphabetically.
/// 3. `getAlbum` lists each album's songs, a few albums at a time.
///
/// Songs in formats iOS plays stream as the original file (`format=raw`), so seeking uses byte
/// ranges. Other formats (OGG, Opus, WMA, ...) are asked for as MP3, which the server transcodes.
/// Credentials go only to the server's host, as a salted token; never as the password itself.
public struct OpenSubsonicLoader: Sendable {
    public static let pageSize = 500
    public static let maxAlbums = 20_000
    static let maxResponseBytes = 32 * 1024 * 1024

    private let client: StreamingHTTPClient
    private let albumConcurrency: Int

    public init(client: StreamingHTTPClient, albumConcurrency: Int = 6) {
        self.client = client
        self.albumConcurrency = max(1, albumConcurrency)
    }

    /// Checks the address and sign-in only. Returns the server software's name when it says.
    @discardableResult
    public func verify(serverURL: URL, credentials: OpenSubsonicCredentials) async throws -> String? {
        let session = try Session(client: client, serverURL: serverURL, credentials: credentials)
        return try await session.ping()
    }

    public func load(serverURL: URL, credentials: OpenSubsonicCredentials) async throws -> LoadedLibrary {
        let session = try Session(client: client, serverURL: serverURL, credentials: credentials)
        _ = try await session.ping()

        var warnings: [String] = []
        let albumIDs = try await listAlbums(session: session, warnings: &warnings)
        let albums = await albumDetails(albumIDs, session: session)

        var tracks: [RemoteTrack] = []
        var seen: Set<String> = []
        var transcoded = 0
        for album in albums.compactMap({ $0 }) {
            for song in album.song?.values ?? [] where song.isVideo != true {
                guard seen.insert(song.id.value).inserted,
                      let track = Self.track(for: song, in: album, endpoints: session.endpoints) else { continue }
                if track.url.query?.contains("format=mp3") == true {
                    transcoded += 1
                }
                tracks.append(track)
            }
        }
        let failed = albums.filter { $0 == nil }.count
        if failed > 0 {
            warnings.append("\(failed) album\(failed == 1 ? "" : "s") couldn't be read and will be tried again next refresh.")
        }
        if transcoded > 0 {
            warnings.append("\(transcoded) song\(transcoded == 1 ? " is" : "s are") in a format iOS can't play, "
                            + "so the server converts \(transcoded == 1 ? "it" : "them") to MP3 while streaming.")
        }
        return LoadedLibrary(name: serverURL.host, tracks: tracks, warnings: warnings)
    }

    // MARK: - Steps

    private func listAlbums(session: Session, warnings: inout [String]) async throws -> [String] {
        var ids: [String] = []
        var seen: Set<String> = []
        var offset = 0
        while true {
            let page: OpenSubsonicAlbumList? = try await session.request(session.endpoints.albumList(offset: offset, size: Self.pageSize))
            let albums = page?.album?.values ?? []
            for album in albums where seen.insert(album.id.value).inserted {
                ids.append(album.id.value)
            }
            offset += albums.count
            if albums.count < Self.pageSize {
                break
            }
            if ids.count >= Self.maxAlbums {
                warnings.append("Only the first \(Self.maxAlbums) albums were listed.")
                break
            }
        }
        return ids
    }

    /// Each album's details, in `ids` order; nil where the request failed.
    private func albumDetails(_ ids: [String], session: Session) async -> [OpenSubsonicAlbumDetail?] {
        var results = [OpenSubsonicAlbumDetail?](repeating: nil, count: ids.count)
        await withTaskGroup(of: (Int, OpenSubsonicAlbumDetail?).self) { group in
            var next = 0
            func addTask() {
                let index = next
                let id = ids[index]
                group.addTask {
                    let detail: OpenSubsonicAlbumDetail? = try? await session.request(session.endpoints.album(id: id))
                    return (index, detail)
                }
                next += 1
            }
            while next < min(albumConcurrency, ids.count) {
                addTask()
            }
            while let (index, detail) = await group.next() {
                results[index] = detail
                if next < ids.count {
                    addTask()
                }
            }
        }
        return results
    }

    // MARK: - Mapping

    static func track(for song: OpenSubsonicSong, in album: OpenSubsonicAlbumDetail, endpoints: OpenSubsonicEndpoints) -> RemoteTrack? {
        let id = song.id.value
        let suffix = song.suffix?.lowercased()
            ?? song.contentType.flatMap(AudioFileType.fileExtension(forMIMEType:))
            ?? song.path.map { ($0 as NSString).pathExtension.lowercased() }
        let isPlayable = suffix.map(AudioFileType.isPlayable(fileExtension:)) ?? false
        let streamURL = isPlayable
            ? endpoints.stream(id: id)
            : endpoints.url("stream", ["id": id, "format": "mp3", "estimateContentLength": "true"])
        guard let url = streamURL else { return nil }

        let fileTitle = song.path.map { TrackTitleCleaner.title(fromFileName: ($0 as NSString).lastPathComponent) }
        var track = RemoteTrack(
            remoteID: id,
            title: nonEmpty(song.title) ?? fileTitle ?? "Unknown song",
            url: url,
            artist: nonEmpty(song.artist) ?? nonEmpty(album.artist),
            album: nonEmpty(song.album) ?? nonEmpty(album.name),
            duration: song.duration.map { TimeInterval($0.value) }
        )
        if isPlayable, let suffix {
            track.mimeType = AudioFileType.mimeType(forExtension: suffix) ?? song.contentType
            track.size = song.size.map { Int64($0.value) }
        } else {
            track.mimeType = "audio/mpeg"
        }
        if let cover = song.coverArt ?? album.coverArt {
            track.artworkURL = endpoints.coverArt(id: cover.value)
        }
        return track
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension OpenSubsonicLoader {
    /// One refresh's requests: one salt, one authorization, one server.
    struct Session: Sendable {
        let client: StreamingHTTPClient
        let endpoints: OpenSubsonicEndpoints
        let authorization: RequestAuthorization

        init(client: StreamingHTTPClient, serverURL: URL, credentials: OpenSubsonicCredentials) throws {
            guard NetworkPolicy.allows(serverURL) else { throw SourceLoadError.blockedURL(serverURL) }
            guard let authorization = credentials.authorization(for: serverURL) else {
                throw SourceLoadError.notAMusicServer
            }
            self.client = client
            self.endpoints = OpenSubsonicEndpoints(serverURL: serverURL)
            self.authorization = authorization
        }

        /// Pings the server; returns its software name (`type`) when it reports one.
        func ping() async throws -> String? {
            let response: OpenSubsonicResponse<OpenSubsonicNothing> = try await envelope(endpoints.ping, isPing: true)
            _ = try unwrap(response)
            return response.type
        }

        func request<Payload: OpenSubsonicPayload>(_ url: URL?) async throws -> Payload? {
            try unwrap(try await envelope(url, isPing: false))
        }

        private func unwrap<Payload>(_ response: OpenSubsonicResponse<Payload>) throws -> Payload? {
            do {
                return try response.unwrap()
            } catch let error as OpenSubsonicError {
                throw SourceLoadError.openSubsonic(error)
            }
        }

        private func envelope<Payload>(_ url: URL?, isPing: Bool) async throws -> OpenSubsonicResponse<Payload> {
            guard let url else { throw SourceLoadError.notAMusicServer }
            let data: Data
            do {
                data = try await client.data(url, authorization: authorization, headers: ["Accept": "application/json"],
                                             maxBytes: OpenSubsonicLoader.maxResponseBytes).data
            } catch let error as HTTPClientError {
                // A web server that isn't a music server usually answers 404 at /rest/ping.
                if isPing, let status = error.statusCode, status == 404 || status == 405 {
                    throw SourceLoadError.notAMusicServer
                }
                throw SourceLoadError.from(error, gitHub: false, hasToken: true)
            }
            do {
                return try JSONDecoder().decode(OpenSubsonicEnvelope<Payload>.self, from: data).response
            } catch {
                throw isPing
                    ? SourceLoadError.notAMusicServer
                    : SourceLoadError.network("The music server sent a response Sonus couldn't read.")
            }
        }
    }
}
