import SwiftUI

/// The top of every tab: the avatar (opens Profile & settings), the page title, and optional
/// trailing buttons.
struct TabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    @EnvironmentObject private var shell: ShellState
    @EnvironmentObject private var authManager: AuthenticationManager

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                shell.push(.profile)
            } label: {
                AvatarView(initials: authManager.currentUser?.initials ?? "", size: 34)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Profile and settings")

            Text(title)
                .font(.emberPageTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            trailing()
        }
        .frame(minHeight: 44)
    }
}

/// A round icon button for headers ("+", search).
struct HeaderIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}

/// Ranks songs for a free-text query across title, album, publisher and artist.
enum LibrarySearch {
    static func rank(_ rawQuery: String, in songs: [Song]) -> [Song] {
        let terms = normalize(rawQuery).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return songs }

        return songs
            .compactMap { song -> (song: Song, score: Int)? in
                let score = score(for: song, terms: terms)
                return score > 0 ? (song, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.song.title.localizedCaseInsensitiveCompare(rhs.song.title) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .map(\.song)
    }

    static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func score(for song: Song, terms: [String]) -> Int {
        let title = normalize(song.title)
        let album = normalize(song.albumName ?? "")
        let publisher = normalize(song.productionHouse ?? "")
        let artist = normalize(song.artist ?? "")
        let fullText = [title, album, publisher, artist].joined(separator: " ")

        var total = 0
        for term in terms {
            let candidates: [(matches: Bool, score: Int)] = [
                (title == term, 140),
                (title.hasPrefix(term), 100),
                (title.localizedStandardContains(term), 78),
                (album.hasPrefix(term), 66),
                (publisher.hasPrefix(term), 62),
                (album.localizedStandardContains(term), 56),
                (publisher.localizedStandardContains(term), 52),
                (artist.localizedStandardContains(term), 48),
                (fullText.localizedStandardContains(term), 38)
            ]
            guard let best = candidates.filter(\.matches).map(\.score).max() else { return 0 }
            total += best
        }
        return total
    }
}
