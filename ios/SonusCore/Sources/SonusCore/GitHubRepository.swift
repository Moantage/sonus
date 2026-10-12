import Foundation

/// A GitHub repository used as a music source.
public struct GitHubRepository: Codable, Hashable, Sendable, CustomStringConvertible {
    public let owner: String
    public let name: String
    /// The branch to read; nil means the repository's default branch.
    public let branch: String?
    /// A folder inside the repository, without leading or trailing slashes; nil for the root.
    public let subfolder: String?

    /// Validates the parts. Returns nil for names GitHub doesn't allow or a subfolder that
    /// climbs out of the repository.
    public init?(owner: String, name: String, branch: String? = nil, subfolder: String? = nil) {
        guard Self.isValidOwner(owner), Self.isValidName(name) else { return nil }
        let branch = branch?.trimmingCharacters(in: .whitespaces)
        if let branch, !branch.isEmpty, !Self.isValidBranch(branch) { return nil }
        guard let folder = Self.normalizedFolder(subfolder) else { return nil }
        self.owner = owner
        self.name = name
        self.branch = (branch?.isEmpty ?? true) ? nil : branch
        self.subfolder = folder.isEmpty ? nil : folder
    }

    /// Parses `owner/repo`, `owner/repo@branch` or `owner/repo/sub/folder@branch`.
    public static func parse(_ text: String) -> GitHubRepository? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard let location = pieces.first else { return nil }
        let branch = pieces.count == 2 ? String(pieces[1]) : nil
        if branch?.isEmpty == true { return nil }
        let parts = location.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let folder = parts.dropFirst(2).joined(separator: "/")
        return GitHubRepository(owner: parts[0], name: parts[1], branch: branch, subfolder: folder.isEmpty ? nil : folder)
    }

    /// `https://github.com/<owner>/<repo>`.
    public var webURL: URL {
        URL(string: "https://github.com/\(owner)/\(name)") ?? URL(fileURLWithPath: "/")
    }

    /// Same repository and folder; the branch may differ only when one side follows the default.
    public func isSameLocation(as other: GitHubRepository) -> Bool {
        owner.lowercased() == other.owner.lowercased()
            && name.lowercased() == other.name.lowercased()
            && subfolder == other.subfolder
            && (branch == nil || other.branch == nil || branch == other.branch)
    }

    /// The repository path of a file in the configured folder.
    public func path(inFolder file: String) -> String {
        guard let subfolder else { return file }
        return "\(subfolder)/\(file)"
    }

    /// True when `path` is inside the configured folder (or anywhere, without one).
    public func contains(path: String) -> Bool {
        guard let subfolder else { return true }
        return path.hasPrefix(subfolder + "/")
    }

    public var description: String {
        var text = "\(owner)/\(name)"
        if let subfolder { text += "/\(subfolder)" }
        if let branch { text += "@\(branch)" }
        return text
    }

    // GitHub user and organization names: letters, digits and single hyphens, up to 39 characters.
    static func isValidOwner(_ owner: String) -> Bool {
        (1...39).contains(owner.count)
            && owner.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            && !owner.hasPrefix("-")
    }

    static func isValidName(_ name: String) -> Bool {
        (1...100).contains(name.count) && name != "." && name != ".."
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-._".contains($0)) }
    }

    // A conservative subset of git-check-ref-format.
    static func isValidBranch(_ branch: String) -> Bool {
        guard branch.count <= 255, !branch.hasPrefix("/"), !branch.hasSuffix("/"), !branch.hasSuffix(".lock"),
              !branch.contains(".."), !branch.contains("//"), !branch.contains("@{") else {
            return false
        }
        return branch.unicodeScalars.allSatisfy { scalar in
            scalar.value > 0x20 && scalar.value != 0x7F && !"~^:?*[\\".unicodeScalars.contains(scalar)
        }
    }

    /// Trims slashes; nil when a component is `.` or `..`.
    static func normalizedFolder(_ folder: String?) -> String? {
        guard let folder else { return "" }
        let components = folder.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        return components.joined(separator: "/")
    }
}

/// Where GitHub's API, raw files and LFS media live. Tests point these at a local server.
public struct GitHubEndpoints: Hashable, Sendable {
    public let api: URL
    public let raw: URL
    public let media: URL

    public init(api: URL, raw: URL, media: URL) {
        self.api = api
        self.raw = raw
        self.media = media
    }

    public static let github = GitHubEndpoints(
        api: URL(string: "https://api.github.com")!,
        raw: URL(string: "https://raw.githubusercontent.com")!,
        media: URL(string: "https://media.githubusercontent.com/media")!
    )

    /// The only hosts a GitHub token is sent to.
    public var hosts: Set<String> {
        Set([api, raw, media].compactMap { $0.host?.lowercased() })
    }

    /// `GET /repos/{owner}/{repo}`.
    public func repository(_ repo: GitHubRepository) -> URL? {
        api(path: "repos/\(repo.owner)/\(repo.name)")
    }

    /// `GET /repos/{owner}/{repo}/git/trees/{ref}`, recursive or not.
    public func tree(_ repo: GitHubRepository, ref: String, recursive: Bool) -> URL? {
        let encodedRef = GitHubPath.encodeSegment(ref)
        return api(path: "repos/\(repo.owner)/\(repo.name)/git/trees/\(encodedRef)", query: recursive ? "recursive=1" : nil)
    }

    /// `GET /repos/{owner}/{repo}/contents/{path}?ref={ref}`.
    public func contents(_ repo: GitHubRepository, path: String, ref: String) -> URL? {
        let query = "ref=" + GitHubPath.encodeSegment(ref)
        return api(path: "repos/\(repo.owner)/\(repo.name)/contents/\(GitHubPath.encode(path))", query: query)
    }

    /// A file's raw URL at `ref`. Each path segment is percent-encoded; the ref keeps its slashes.
    public func raw(_ repo: GitHubRepository, ref: String, path: String) -> URL? {
        Self.join(raw, "\(repo.owner)/\(repo.name)/\(GitHubPath.encode(ref))/\(GitHubPath.encode(path))")
    }

    /// A Git LFS file's media URL at `ref`.
    public func media(_ repo: GitHubRepository, ref: String, path: String) -> URL? {
        Self.join(media, "\(repo.owner)/\(repo.name)/\(GitHubPath.encode(ref))/\(GitHubPath.encode(path))")
    }

    /// The repository path of a raw URL for `repo` at `ref`, or nil if it points elsewhere.
    public func repositoryPath(ofRawURL url: URL, repo: GitHubRepository, ref: String) -> String? {
        guard let prefixURL = raw(repo, ref: ref, path: ""),
              url.host?.lowercased() == prefixURL.host?.lowercased(), url.port == prefixURL.port else {
            return nil
        }
        let prefix = prefixURL.path.hasSuffix("/") ? prefixURL.path : prefixURL.path + "/"
        let path = url.path
        guard path.hasPrefix(prefix), path.count > prefix.count else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    private func api(path: String, query: String? = nil) -> URL? {
        let joined = Self.join(api, path)
        guard let query, let joined else { return joined }
        return URL(string: joined.absoluteString + "?" + query)
    }

    private static func join(_ base: URL, _ encodedPath: String) -> URL? {
        let baseString = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        return URL(string: baseString + "/" + encodedPath)
    }
}

/// Percent-encoding for repository paths.
public enum GitHubPath {
    /// RFC 3986 unreserved characters. Everything else, including spaces, parentheses, commas
    /// and non-ASCII letters, is percent-encoded as UTF-8.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Encodes each `/`-separated segment and keeps the slashes.
    public static func encode(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { encodeSegment(String($0)) }
            .joined(separator: "/")
    }

    /// Encodes one segment, slashes included.
    public static func encodeSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: unreserved) ?? segment
    }
}
