import SwiftUI
import UniformTypeIdentifiers

/// The signed-in app shell: Home / Search / Your Library tabs, the persistent mini-player
/// above the tab bar, and Now Playing, which grows out of the mini-player.
struct ContentView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var store: StoreManager

    @StateObject private var shell = ShellState()
    @StateObject private var ads = FullScreenAdController()
    @Namespace private var playerNamespace
    /// The mini-player and tab bar step aside while the keyboard is up.
    @State private var isKeyboardVisible = false

    private var hasSong: Bool { player.currentSong != nil }

    var body: some View {
        ZStack {
            Theme.backgroundBase.ignoresSafeArea()

            VStack(spacing: 0) {
                tabs
                if !isKeyboardVisible {
                    bottomChrome
                }
            }
            .accessibilityHidden(shell.isPlayerExpanded)

            if shell.isPlayerExpanded, hasSong {
                NowPlayingView(namespace: playerNamespace)
                    .zIndex(2)
            }
        }
        .environmentObject(shell)
        .fileImporter(
            isPresented: $shell.isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let before = libraryStore.songs.count
                libraryStore.importFiles(from: urls)
                let added = libraryStore.songs.count - before
                if added > 0 { shell.showToast(added == 1 ? "Added 1 song" : "Added \(added) songs") }
            case .failure(let error):
                libraryStore.lastImportError = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $shell.isCreatePlaylistPresented) {
            CreatePlaylistView()
                .environmentObject(shell)
        }
        .alert("Library Error", isPresented: libraryErrorBinding) {
            Button("OK", role: .cancel) { libraryStore.lastImportError = nil }
        } message: {
            Text(libraryStore.lastImportError ?? "Something went wrong.")
        }
        .alert("Playback Error", isPresented: playbackErrorBinding) {
            Button("OK", role: .cancel) { player.lastPlaybackError = nil }
        } message: {
            Text(player.lastPlaybackError ?? "This track could not be played.")
        }
        .task {
            player.syncLibrary(with: libraryStore.songs)
            #if DEBUG
            // Screenshot runs can't answer the tracking prompt or close an ad.
            if UIReviewScreen.requested != nil { return }
            #endif
            ads.attach(player: player, store: store)
            await ads.handleLaunch()
        }
        #if DEBUG
        .task { await UIReviewScreen.open(shell: shell, player: player, library: libraryStore) }
        #endif
        .onChange(of: player.currentSong?.id) { _ in
            ads.songDidChange()
        }
        .onChange(of: libraryStore.songs) { songs in
            player.syncLibrary(with: songs)
        }
        .onChange(of: hasSong) { hasSong in
            if !hasSong { shell.isPlayerExpanded = false }
        }
        .task(id: player.currentSong?.id) {
            await shell.updateArtworkTint(song: player.currentSong, image: player.artworkImage)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .haptic(.light, trigger: shell.playRequestCount)
        .haptic(.soft(1), trigger: shell.isPlayerExpanded)
    }

    // MARK: Tabs

    /// A system TabView with its tab bar hidden (Ember draws its own): each tab keeps its scroll
    /// position and navigation stack, and inactive tabs leave the screen, VoiceOver included.
    /// iOS 15 can't hide a TabView's bar, so there the tabs are stacked and only the selected
    /// one is shown, which keeps the same behaviour.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 16.0, *), !DeviceProfile.usesLegacyUI {
            TabView(selection: $shell.selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    tabStack(for: tab)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(tab)
                }
            }
        } else {
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    // A tab is built the first time it's opened, as TabView does.
                    if shell.visitedTabs.contains(tab) {
                        let isSelected = shell.selectedTab == tab
                        tabStack(for: tab)
                            .opacity(isSelected ? 1 : 0)
                            .allowsHitTesting(isSelected)
                            .accessibilityHidden(!isSelected)
                            .zIndex(isSelected ? 1 : 0)
                    }
                }
            }
        }
    }

    private func tabStack(for tab: AppTab) -> some View {
        RouteNavigationStack(path: shell.path(for: tab)) {
            root(for: tab)
        } destination: { route in
            destination(for: route)
        }
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .search: SearchView()
        case .library: LibraryView()
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .profile:
            ProfileView()
        case .collection(let collection):
            SongCollectionView(collection: collection)
        }
    }

    // MARK: Bottom chrome

    private var bottomChrome: some View {
        VStack(spacing: ScreenMetrics.isCompact ? 4 : 6) {
            if hasSong {
                MiniPlayerView(namespace: playerNamespace)
                    .padding(.horizontal, ScreenMetrics.isCompact ? 6 : 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            EmberTabBar(selection: $shell.selectedTab) { tab in
                shell.popToRoot(tab)
            }
        }
        .animation(Theme.Motion.glide, value: hasSong)
        // The toast floats above the chrome so it never shifts the content's insets.
        .overlay(alignment: .top) {
            if let toast = shell.toast {
                ToastView(message: toast)
                    .alignmentGuide(.top) { $0[.bottom] + 8 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: Theme.backgroundBase.opacity(0), location: 0),
                    .init(color: Theme.backgroundBase.opacity(0.92), location: 0.45),
                    .init(color: Theme.backgroundBase, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Fade the content above into the chrome.
            .padding(.top, -24)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    // MARK: Alerts

    private var libraryErrorBinding: Binding<Bool> {
        Binding(
            get: { libraryStore.lastImportError != nil },
            set: { if !$0 { libraryStore.lastImportError = nil } }
        )
    }

    private var playbackErrorBinding: Binding<Bool> {
        Binding(
            get: { player.lastPlaybackError != nil },
            set: { if !$0 { player.lastPlaybackError = nil } }
        )
    }
}

// MARK: - Tab bar

/// Home / Search / Your Library. Tapping the selected tab again returns it to its first page.
struct EmberTabBar: View {
    @Binding var selection: AppTab
    let onReselect: (AppTab) -> Void

    /// Bumped per tab on every tap, so only the tapped icon bounces.
    @State private var bounces: [AppTab: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    bounces[tab, default: 0] += 1
                    if isSelected {
                        onReselect(tab)
                    } else {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: ScreenMetrics.isCompact ? 2 : 4) {
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: ScreenMetrics.tabIconSize, weight: isSelected ? .semibold : .regular))
                            .symbolBounce(value: bounces[tab, default: 0], down: true)
                            .frame(height: ScreenMetrics.tabIconSize + 4)
                        Text(tab.title)
                            .font(.system(size: ScreenMetrics.isCompact ? 10 : 11, weight: .medium))
                    }
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSubtle)
                    .animation(Theme.Motion.snappy, value: isSelected)
                    .frame(maxWidth: .infinity, minHeight: ScreenMetrics.tabBarHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.9))
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityShowsLargeContentViewer {
                    Image(systemName: tab.icon)
                    Text(tab.title)
                }
            }
        }
        .padding(.top, 2)
        .haptic(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityTabBarTrait()
    }
}

// MARK: - Toast

/// Short confirmation ("Added to Road trip") above the mini-player.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(.subheadline).weight(.semibold))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .padding(.horizontal, 8)
            .accessibilityAddTraits(.updatesFrequently)
            .onAppear {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
    }
}
