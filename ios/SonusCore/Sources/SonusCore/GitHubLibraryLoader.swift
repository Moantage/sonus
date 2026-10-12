import Foundation

/// Lists a GitHub repository as a music library.
///
/// 1. Resolves the branch (the repository's default when none is set).
/// 2. Reads the Git tree. A truncated recursive listing falls back to walking folders one by one.
/// 3. Uses `sonus.json` from the folder (or root) when there is one, fetched through the
///    contents API; otherwise every playable audio file becomes a track, keyed by its path.
/// 4. Swaps Git LFS pointers for their media URLs, so the real audio streams.
///
/// A token, when given, goes only to the hosts in ``GitHubEndpoints/hosts``.
public struct GitHubLibraryLoader: Sendable {
    public static let maxTreeBytes = 48 * 1024 * 1024

    private let client: StreamingHTTPClient
    private let endpoints: GitHubEndpoints
    private let maxFolderRequests: Int
    private let lfsConcurrency: Int

    public init(
        client: StreamingHTTPClient,
        endpoints: GitHubEndpoints = .github,
        maxFolderRequests: Int = 300,
        lfsConcurrency: Int = 6
    ) {
        self.client = client
        self.endpoints = endpoints
        self.maxFolderRequests = maxFolderRequests
        self.lfsConcurrency = max(1, lfsConcurrency)
    }

    public func load(_ repository: GitHubRepository, token: String?) async throws -> LoadedLibrary {
        let session = Session(
            client: client,
            endpoints: endpoints,
            authorization: token.map { RequestAuthorization.gitHub(token: $0, endpoints: endpoints) }
        )
        let branch = try await resolveBranch(of: repository, session: session)
        var warnings: [String] = []
        let entries = try await listFiles(of: repository, ref: branch, session: session, warnings: &warnings)
        let entriesByPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        var library: LoadedLibrary
        let manifestPath = GitHubTreeLibrary.manifestPath(for: repository)
        if entriesByPath[manifestPath]?.isBlob == true {
            library = try await manifestLibrary(repository, ref: branch, path: manifestPath, session: session)
        } else {
            let tracks = GitHubTreeLibrary.audioEntries(in: entries, repository: repository).compactMap {
                GitHubTreeLibrary.track(for: $0, repository: repository, ref: branch, endpoints: endpoints)
            }
            library = LoadedLibrary(name: repository.name, tracks: tracks)
        }
        library.tracks = await resolvingLFS(library.tracks, repository: repository, ref: branch,
                                            entries: entriesByPath, session: session)
        library.warnings = warnings + library.warnings
        return library
    }

    // MARK: - Steps

    private func resolveBranch(of repository: GitHubRepository, session: Session) async throws -> String {
        if let branch = repository.branch {
            return branch
        }
        let info: GitHubRepositoryInfo = try await session.json(endpoints.repository(repository))
        return info.defaultBranch
    }

    private func listFiles(
        of repository: GitHubRepository,
        ref: String,
        session: Session,
        warnings: inout [String]
    ) async throws -> [GitTree.Entry] {
        let tree: GitTree = try await session.json(endpoints.tree(repository, ref: ref, recursive: true), maxBytes: Self.maxTreeBytes)
        guard tree.truncated else {
            return tree.tree
        }
        return try await walkFolders(of: repository, rootSHA: tree.sha, session: session, warnings: &warnings)
    }

    /// Lists folder by folder, only descending where the configured subfolder can be.
    private func walkFolders(
        of repository: GitHubRepository,
        rootSHA: String,
        session: Session,
        warnings: inout [String]
    ) async throws -> [GitTree.Entry] {
        var pending: [(prefix: String, sha: String)] = [("", rootSHA)]
        var files: [GitTree.Entry] = []
        var requests = 0
        while !pending.isEmpty, requests < maxFolderRequests {
            let folder = pending.removeFirst()
            requests += 1
            let tree: GitTree = try await session.json(endpoints.tree(repository, ref: folder.sha, recursive: false),
                                                       maxBytes: Self.maxTreeBytes)
            for var entry in tree.tree {
                entry.path = folder.prefix + entry.path
                if entry.isTree, Self.mayContainFiles(entry.path, of: repository) {
                    pending.append((entry.path + "/", entry.sha))
                } else if entry.isBlob {
                    files.append(entry)
                }
            }
        }
        if !pending.isEmpty {
            warnings.append("This repository is too large to list completely. Add a sonus.json or pick a smaller folder.")
        }
        return files
    }

    /// Whether `folder` is the configured subfolder, inside it, or on the way to it.
    static func mayContainFiles(_ folder: String, of repository: GitHubRepository) -> Bool {
        guard let subfolder = repository.subfolder else { return true }
        return folder == subfolder || folder.hasPrefix(subfolder + "/") || subfolder.hasPrefix(folder + "/")
    }

    private func manifestLibrary(_ repository: GitHubRepository, ref: String, path: String,
                                 session: Session) async throws -> LoadedLibrary {
        guard let contentsURL = endpoints.contents(repository, path: path, ref: ref),
              let manifestURL = endpoints.raw(repository, ref: ref, path: path) else {
            throw SourceLoadError.missingRepository
        }
        let data = try await session.data(contentsURL, accept: "application/vnd.github.raw+json",
                                          maxBytes: ManifestLoader.maxManifestBytes)
        return try ManifestLoader.library(from: data, manifestURL: manifestURL)
    }

    /// Points LFS-tracked tracks at their media URL, checking each small file's content.
    private func resolvingLFS(
        _ tracks: [RemoteTrack],
        repository: GitHubRepository,
        ref: String,
        entries: [String: GitTree.Entry],
        session: Session
    ) async -> [RemoteTrack] {
        let candidates: [(index: Int, path: String)] = tracks.indices.compactMap { index in
            guard let path = endpoints.repositoryPath(ofRawURL: tracks[index].url, repo: repository, ref: ref),
                  let entry = entries[path], GitHubTreeLibrary.mightBeLFSPointer(entry) else {
                return nil
            }
            return (index, path)
        }
        guard !candidates.isEmpty else { return tracks }

        var resolved = tracks
        var remaining = candidates[...]
        await withTaskGroup(of: LFSCheck.self) { group in
            var running = 0
            while !remaining.isEmpty || running > 0 {
                while running < lfsConcurrency, let candidate = remaining.popFirst() {
                    let url = tracks[candidate.index].url
                    group.addTask {
                        let data = try? await session.data(url, accept: nil, maxBytes: LFSPointer.maxSize)
                        return LFSCheck(index: candidate.index, path: candidate.path, pointer: data.flatMap(LFSPointer.parse))
                    }
                    running += 1
                }
                guard let check = await group.next() else { break }
                running -= 1
                if let pointer = check.pointer, let mediaURL = endpoints.media(repository, ref: ref, path: check.path) {
                    resolved[check.index].url = mediaURL
                    resolved[check.index].size = pointer.size
                    resolved[check.index].sha256 = pointer.oid
                    resolved[check.index].revision = pointer.oid
                }
            }
        }
        return resolved
    }
}

// MARK: - Requests

/// The part of `GET /repos/{owner}/{repo}` the loader needs.
private struct GitHubRepositoryInfo: Decodable {
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case defaultBranch = "default_branch"
    }
}

extension GitHubLibraryLoader {
    struct LFSCheck: Sendable {
        let index: Int
        let path: String
        let pointer: LFSPointer?
    }

    /// One refresh's requests: shared client, endpoints and authorization.
    struct Session: Sendable {
        let client: StreamingHTTPClient
        let endpoints: GitHubEndpoints
        let authorization: RequestAuthorization?

        func data(_ url: URL?, accept: String?, maxBytes: Int) async throws -> Data {
            guard let url else { throw SourceLoadError.missingRepository }
            var headers = ["X-GitHub-Api-Version": "2022-11-28"]
            if let accept {
                headers["Accept"] = accept
            }
            do {
                return try await client.data(url, authorization: authorization, headers: headers, maxBytes: maxBytes).data
            } catch let error as HTTPClientError {
                throw SourceLoadError.from(error, gitHub: true, hasToken: authorization != nil)
            }
        }

        func json<Value: Decodable>(_ url: URL?, maxBytes: Int = 4 * 1024 * 1024) async throws -> Value {
            let data = try await data(url, accept: "application/vnd.github+json", maxBytes: maxBytes)
            do {
                return try JSONDecoder().decode(Value.self, from: data)
            } catch {
                throw SourceLoadError.network("GitHub sent a response Sonus couldn't read.")
            }
        }
    }
}
