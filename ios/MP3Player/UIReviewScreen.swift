#if DEBUG
import SonusCore
import SwiftUI

/// DEBUG only: `-SonusUIReviewScreen <screen>` (with `-SonusUIReview`) opens one screen after
/// launch, so layouts can be screenshotted in a Simulator that can't be tapped, for example to
/// check the iPod touch layout with `-SonusSimulateIPod`. Release builds don't contain it.
enum UIReviewScreen: String {
    case home
    case search
    case library
    case collection
    case profile
    case paywall
    case createPlaylist
    case nowPlaying
    case queue
    case controls
    case actions

    static let requested: UIReviewScreen? = LaunchArguments
        .value(for: "SonusUIReviewScreen", in: ProcessInfo.processInfo.arguments)
        .flatMap(UIReviewScreen.init(rawValue:))

    /// Opens the requested screen once the library has songs (a debug manifest loads them).
    @MainActor
    static func open(shell: ShellState, player: AudioPlayerManager, library: LibraryStore) async {
        guard let screen = requested else { return }
        for _ in 0..<50 where library.songs.isEmpty {
            try? await Task.sleep(seconds: 0.2)
        }
        try? await Task.sleep(seconds: 0.5)
        switch screen {
        case .home:
            break
        case .search:
            shell.selectedTab = .search
        case .library:
            shell.selectedTab = .library
        case .collection:
            shell.selectedTab = .library
            shell.paths[.library] = [.collection(.allSongs)]
        case .profile, .paywall:
            shell.push(.profile)
        case .createPlaylist:
            shell.startCreatingPlaylist()
        case .nowPlaying, .queue, .controls, .actions:
            guard let first = library.songs.first else { return }
            shell.play(first, in: library.songs, context: .library, player: player)
            try? await Task.sleep(seconds: 0.5)
            withAnimation(Theme.Motion.glide) { shell.isPlayerExpanded = true }
        }
    }
}
#endif
