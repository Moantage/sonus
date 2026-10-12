import SwiftUI

/// Search: a big field over your library, with browse tiles when it's empty.
struct SearchView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var shell: ShellState

    @State private var query = ""
    @FocusState private var isFieldFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var songResults: [Song] { LibrarySearch.rank(trimmedQuery, in: libraryStore.songs) }

    private var playlistResults: [Playlist] {
        let needle = LibrarySearch.normalize(trimmedQuery)
        return libraryStore.playlists.filter { LibrarySearch.normalize($0.name).localizedStandardContains(needle) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TabHeader(title: "Search")
                searchField

                if trimmedQuery.isEmpty {
                    browse
                } else {
                    results
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.backgroundBase)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accentInk)
                .accessibilityHidden(true)

            TextField(
                "Search your library",
                text: $query,
                prompt: Text("What do you want to listen to?").foregroundStyle(Theme.accentInk.opacity(0.55))
            )
            .font(.system(.body, weight: .medium))
            .foregroundStyle(Theme.accentInk)
            .tint(Theme.accentInk)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isFieldFocused)
            .accessibilityLabel("Search your library")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: Browse

    private var browse: some View {
        let collections: [SongCollection] = [.allSongs, .recentlyAdded, .downloaded]
            + libraryStore.playlists.map { .playlist($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Browse your library")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(collections, id: \.self) { collection in
                    BrowseTile(collection: collection)
                }
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if songResults.isEmpty && playlistResults.isEmpty {
            VStack(spacing: 8) {
                Text("Couldn't find “\(trimmedQuery)”")
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Try another song, album or artist.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSubtle)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(playlistResults) { playlist in
                    LibraryItemRow(collection: .playlist(playlist.id))
                }
                SongList(songs: songResults, context: .search)
            }
        }
    }
}

/// A colourful browse tile with tilted artwork in the corner.
private struct BrowseTile: View {
    let collection: SongCollection

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var shell: ShellState

    var body: some View {
        Button {
            shell.push(.collection(collection))
        } label: {
            ZStack(alignment: .topLeading) {
                tileColor
                Text(collection.title(in: libraryStore))
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .padding(12)
                    .padding(.trailing, 36)
            }
            .frame(height: 96)
            .overlay(alignment: .bottomTrailing) {
                CollectionArtwork(collection: collection, songs: collection.songs(in: libraryStore), size: 58)
                    .rotationEffect(.degrees(24))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .offset(x: 14, y: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96))
        .accessibilityLabel(collection.title(in: libraryStore))
    }

    private var tileColor: Color {
        let seed: UUID
        switch collection {
        case .playlist(let id): seed = id
        case .allSongs: seed = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
        case .recentlyAdded: seed = UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID()
        case .downloaded: seed = UUID(uuidString: "00000000-0000-0000-0000-000000000005") ?? UUID()
        }
        return ArtworkPalette.backdrop(from: ArtworkPalette.baseColor(for: seed), brightness: 0.36...0.5)
    }
}
