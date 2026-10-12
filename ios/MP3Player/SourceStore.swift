import Foundation
import SonusCore

/// The person's music sources: Sonus Manifests and GitHub repositories today, Sonus Server and
/// OpenSubsonic later.
///
/// The list lives in Application Support (`sources.json`) and holds no secrets. A source's token
/// lives only in the Keychain, under the source's ``MusicSource/credentialKey``, and is sent
/// only to the hosts its ``RequestAuthorization`` allows. It never goes to Firestore,
/// UserDefaults or logs.
@MainActor
final class SourceStore: ObservableObject {
    static let shared = SourceStore()

    enum RefreshState: Equatable {
        case idle
        case refreshing
        case succeeded(refreshedAt: Date, summary: SourceMergeSummary, warnings: [String])
        case failed(String)
    }

    /// How a song from a source streams.
    struct StreamingAccess {
        /// Stream through ``AuthorizedResourceLoader`` instead of AVPlayer's own HTTP stack.
        let usesLoader: Bool
        /// The secret header to send, if the source has one.
        let authorization: RequestAuthorization?
    }

    enum StoreError: Error, CustomStringConvertible {
        case unknownSource

        var description: String { "That source no longer exists." }
    }

    /// Sources not refreshed for this long are refreshed in the background at launch.
    static let staleAfter: TimeInterval = 12 * 60 * 60

    @Published private(set) var sources: [MusicSource] = []
    @Published private(set) var refreshStates: [MusicSource.ID: RefreshState] = [:]
    @Published var lastError: String?

    /// The HTTP client for listing sources and for streaming through the resource loader.
    let httpClient = StreamingHTTPClient()
    private(set) var gitHubEndpoints: GitHubEndpoints = .github

    private let fileURL: URL
    private var refreshTasks: [MusicSource.ID: Task<SourceMergeSummary, Error>] = [:]

    init(fileURL: URL = AppPaths.sourcesFileURL) {
        self.fileURL = fileURL
        loadFromDisk()
    }

    func source(id: MusicSource.ID?) -> MusicSource? {
        guard let id else { return nil }
        return sources.first { $0.id == id }
    }

    // MARK: - Credentials

    func hasCredential(for sourceID: MusicSource.ID) -> Bool {
        source(id: sourceID).flatMap(credential(for:)) != nil
    }

    /// Stores (or, with nil, deletes) a source's secret in the Keychain. It stays readable while the
    /// phone is locked so background playback and downloads keep working, and never leaves the device.
    @discardableResult
    func setCredential(_ secret: String?, for sourceID: MusicSource.ID) -> Bool {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return false }
        let key = sources[index].credentialKey ?? MusicSource.defaultCredentialKey(for: sourceID)
        guard let secret, !secret.isEmpty else {
            _ = KeychainManager.shared.delete(for: key)
            sources[index].credentialKey = nil
            persist()
            return true
        }
        guard KeychainManager.shared.store(secret, for: key, accessibility: .afterFirstUnlock) else { return false }
        if sources[index].credentialKey != key {
            sources[index].credentialKey = key
            persist()
        }
        return true
    }

    /// The header a source's requests carry, built from the Keychain each time it's needed.
    func authorization(for source: MusicSource) -> RequestAuthorization? {
        guard let secret = credential(for: source) else { return nil }
        switch source.kind {
        case .github:
            return .gitHub(token: secret, endpoints: gitHubEndpoints)
        case .manifest, .sonusServer, .openSubsonic:
            guard let host = source.url.host?.lowercased() else { return nil }
            return .bearer(secret, hosts: [host])
        }
    }

    func streamingAccess(for song: Song) -> StreamingAccess {
        guard let source = source(id: song.sourceID) else {
            return StreamingAccess(usesLoader: false, authorization: nil)
        }
        let authorization = authorization(for: source)
        // GitHub serves audio as application/octet-stream; the loader states the real type.
        return StreamingAccess(usesLoader: authorization != nil || source.kind == .github, authorization: authorization)
    }

    private func credential(for source: MusicSource) -> String? {
        guard let key = source.credentialKey, let secret = KeychainManager.shared.retrieve(for: key), !secret.isEmpty else {
            return nil
        }
        return secret
    }

    // MARK: - Adding, refreshing, removing

    /// Adds a Sonus Manifest source, or refreshes it if it's already there. The manifest is read
    /// and validated first: one that can't be read isn't added.
    @discardableResult
    func addManifestSource(url: URL, name: String? = nil, token: String? = nil, into library: LibraryStore) async throws -> MusicSource {
        try await add(.manifest(url: url, name: name), hasCustomName: name != nil, token: token, into: library)
    }

    /// Adds a GitHub repository source, or refreshes it if it's already there. `token` is a
    /// fine-grained personal access token with Contents: read-only; public repositories need none.
    @discardableResult
    func addGitHubSource(
        _ repository: GitHubRepository,
        name: String? = nil,
        token: String? = nil,
        into library: LibraryStore
    ) async throws -> MusicSource {
        try await add(.github(repository, name: name), hasCustomName: name != nil, token: token, into: library)
    }

    /// Re-reads a source and updates its songs in place, matched by the source's stable track IDs.
    @discardableResult
    func refresh(_ sourceID: MusicSource.ID, into library: LibraryStore) async throws -> SourceMergeSummary {
        if let running = refreshTasks[sourceID] {
            return try await running.value
        }
        let task = Task { try await performRefresh(sourceID, into: library) }
        refreshTasks[sourceID] = task
        defer { refreshTasks[sourceID] = nil }
        return try await task.value
    }

    /// Refreshes every source last refreshed more than ``staleAfter`` ago. Failures are recorded in
    /// ``refreshStates``.
    func refreshStaleSources(into library: LibraryStore, now: Date = Date()) async {
        let stale = sources.filter { source in
            source.kind.isSupported && now.timeIntervalSince(source.lastRefreshedAt ?? .distantPast) > Self.staleAfter
        }
        for source in stale {
            _ = try? await refresh(source.id, into: library)
        }
    }

    /// Removes a source, its Keychain secret and its songs (downloads included).
    func removeSource(_ sourceID: MusicSource.ID, from library: LibraryStore) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        let source = sources.remove(at: index)
        if let key = source.credentialKey {
            _ = KeychainManager.shared.delete(for: key)
        }
        refreshStates[sourceID] = nil
        library.removeSongs(fromSource: sourceID)
        persist()
    }

    func rename(_ sourceID: MusicSource.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].name = trimmed
        persist()
    }

    /// A message for a failed add or refresh.
    static func message(for error: Error) -> String {
        if let error = error as? SourceLoadError {
            return error.description
        }
        if let error = error as? HTTPClientError {
            return error.description
        }
        if let error = error as? StoreError {
            return error.description
        }
        return error.localizedDescription
    }

    private func add(
        _ candidate: MusicSource,
        hasCustomName: Bool,
        token: String?,
        into library: LibraryStore
    ) async throws -> MusicSource {
        if let existing = sources.first(where: { $0.isSameLibrary(as: candidate) }) {
            if let token {
                setCredential(token, for: existing.id)
            }
            try await refresh(existing.id, into: library)
            return source(id: existing.id) ?? existing
        }
        guard candidate.kind.isSupported else { throw SourceLoadError.unsupportedKind(candidate.kind) }
        guard NetworkPolicy.allows(candidate.url) else { throw SourceLoadError.blockedURL(candidate.url) }

        // List before saving anything, so a source that can't be read leaves no trace.
        let loaded = try await load(candidate, secret: token)
        var source = candidate
        if !hasCustomName, let name = loaded.name, !name.isEmpty {
            source.name = name
        }
        source.lastRefreshedAt = Date()
        sources.append(source)
        persist()
        if let token {
            setCredential(token, for: source.id)
        }
        apply(loaded, from: source, into: library)
        return self.source(id: source.id) ?? source
    }

    private func performRefresh(_ sourceID: MusicSource.ID, into library: LibraryStore) async throws -> SourceMergeSummary {
        guard let source = source(id: sourceID) else { throw StoreError.unknownSource }
        refreshStates[sourceID] = .refreshing
        do {
            let loaded = try await load(source, secret: credential(for: source))
            // The source may have been removed while it was loading.
            guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { throw StoreError.unknownSource }
            sources[index].lastRefreshedAt = Date()
            persist()
            return apply(loaded, from: sources[index], into: library)
        } catch {
            if self.source(id: sourceID) != nil {
                refreshStates[sourceID] = .failed(Self.message(for: error))
            }
            throw error
        }
    }

    private func load(_ source: MusicSource, secret: String?) async throws -> LoadedLibrary {
        switch source.kind {
        case .manifest:
            let authorization = secret.flatMap { secret in
                source.url.host.map { RequestAuthorization.bearer(secret, hosts: [$0.lowercased()]) }
            }
            return try await ManifestLoader(client: httpClient).load(from: source.url, authorization: authorization)
        case .github:
            guard let repository = source.github else { throw SourceLoadError.missingRepository }
            return try await GitHubLibraryLoader(client: httpClient, endpoints: gitHubEndpoints).load(repository, token: secret)
        case .sonusServer, .openSubsonic:
            throw SourceLoadError.unsupportedKind(source.kind)
        }
    }

    @discardableResult
    private func apply(_ loaded: LoadedLibrary, from source: MusicSource, into library: LibraryStore) -> SourceMergeSummary {
        let summary = library.applySourceLibrary(loaded, from: source)
        refreshStates[source.id] = .succeeded(refreshedAt: Date(), summary: summary, warnings: loaded.warnings)
        TrackTagEnricher.shared.enqueue(library.songs(fromSource: source.id), library: library)
        return summary
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            sources = try SourceList.decode(from: Data(contentsOf: fileURL)).sources
        } catch {
            lastError = "Unable to load your music sources."
        }
    }

    private func persist() {
        do {
            // Readable after the first unlock, so a background relaunch can still find sources.
            try SourceList(sources: sources).encoded()
                .write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            lastError = "Unable to save your music sources."
        }
    }

    #if DEBUG
    /// Points GitHub sources at a local fake GitHub (`-SonusDebugGitHubEndpoint`). Tokens then go
    /// only to that fake's host.
    func useGitHubEndpoints(_ endpoints: GitHubEndpoints) {
        gitHubEndpoints = endpoints
    }
    #endif
}
