#if DEBUG
import Foundation
import SonusCore

/// DEBUG-only launch arguments for trying sources before the add-source screens exist (step 5).
/// Release builds don't contain this file's code.
///
/// - `-SonusDebugManifestURL <url>` adds or refreshes a Sonus Manifest source.
/// - `-SonusDebugGitHubRepo owner/repo[/folder][@branch]` adds or refreshes a GitHub source. A
///   token in the `SONUS_GITHUB_TOKEN` environment variable is read once, saved to the Keychain
///   and removed from the process environment; later launches use the Keychain copy.
/// - `-SonusDebugGitHubEndpoint <url>` sends GitHub requests to a local fake GitHub that serves
///   `api/`, `raw/` and `media/` under that URL. Only local-network hosts are accepted.
@MainActor
enum DebugLaunchHooks {
    static let tokenEnvironmentVariable = "SONUS_GITHUB_TOKEN"
    private static var didRun = false

    static func run(library: LibraryStore, arguments: [String] = ProcessInfo.processInfo.arguments) async {
        guard !didRun else { return }
        didRun = true
        let sources = SourceStore.shared

        if let base = LaunchArguments.value(for: "SonusDebugGitHubEndpoint", in: arguments) {
            if let url = URL(string: base), let host = url.host, NetworkPolicy.isLocal(host: host) {
                sources.useGitHubEndpoints(GitHubEndpoints(
                    api: url.appendingPathComponent("api"),
                    raw: url.appendingPathComponent("raw"),
                    media: url.appendingPathComponent("media")
                ))
                log("GitHub requests go to \(url.absoluteString)")
            } else {
                log("Ignoring -SonusDebugGitHubEndpoint: it must be a local-network URL.")
            }
        }

        if let text = LaunchArguments.value(for: "SonusDebugManifestURL", in: arguments) {
            if let url = URL(string: text) {
                await report("Manifest \(url.absoluteString)", library: library) {
                    try await sources.addManifestSource(url: url, into: library)
                }
            } else {
                log("Ignoring -SonusDebugManifestURL: not a URL.")
            }
        }

        if let text = LaunchArguments.value(for: "SonusDebugGitHubRepo", in: arguments) {
            let token = takeEnvironmentToken()
            if let repository = GitHubRepository.parse(text) {
                await report("GitHub \(repository)", library: library) {
                    try await sources.addGitHubSource(repository, token: token, into: library)
                }
            } else {
                log("Ignoring -SonusDebugGitHubRepo: use owner/repo[/folder][@branch].")
            }
        }
    }

    private static func report(_ label: String, library: LibraryStore, add: () async throws -> MusicSource) async {
        do {
            let source = try await add()
            let count = library.songs(fromSource: source.id).count
            let hasToken = SourceStore.shared.hasCredential(for: source.id)
            log("\(label): \(count) songs (token in Keychain: \(hasToken ? "yes" : "no"))")
        } catch {
            log("\(label) failed: \(SourceStore.message(for: error))")
        }
    }

    /// Reads the token once and removes it from this process's environment. It's never logged.
    private static func takeEnvironmentToken() -> String? {
        guard let raw = getenv(tokenEnvironmentVariable) else { return nil }
        let token = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        unsetenv(tokenEnvironmentVariable)
        return token.isEmpty ? nil : token
    }

    private static func log(_ message: String) {
        print("[Sonus debug] \(message)")
    }
}
#endif
