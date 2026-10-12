import SwiftUI

/// Full-screen "Give your playlist a name" flow. Creates the playlist, then either adds the
/// pending song (when opened from "Add to playlist") or opens the new playlist's page.
struct CreatePlaylistView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var shell: ShellState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var didCreate = false
    @FocusState private var isFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            Theme.glowBackground

            VStack(spacing: 28) {
                Spacer()

                Text("Give your playlist a name")
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 8) {
                    TextField("Playlist name", text: $name)
                        .font(.system(.largeTitle, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.accent)
                        .multilineTextAlignment(.center)
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit(create)
                    Rectangle()
                        .fill(isFocused ? Theme.accent : Theme.outline)
                        .frame(height: 1.5)
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        shell.songForNewPlaylist = nil
                        dismiss()
                    }
                    .buttonStyle(PillButtonStyle(kind: .outline))

                    Button("Create", action: create)
                        .buttonStyle(PillButtonStyle(kind: .primary, isEnabled: !trimmedName.isEmpty))
                        .disabled(trimmedName.isEmpty)
                }
                .padding(.horizontal, 12)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            name = "My playlist #\(libraryStore.playlists.count + 1)"
            isFocused = true
        }
        .sensoryFeedback(.success, trigger: didCreate)
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        libraryStore.createPlaylist(named: trimmedName)
        didCreate = true

        // `createPlaylist` inserts the new playlist first.
        guard let playlist = libraryStore.playlists.first(where: { $0.name == trimmedName }) else {
            dismiss()
            return
        }

        if let song = shell.songForNewPlaylist {
            libraryStore.addSong(song, to: playlist)
            shell.showToast("Added to \(playlist.name)")
        } else {
            shell.openInLibrary(.playlist(playlist.id))
        }
        shell.songForNewPlaylist = nil
        dismiss()
    }
}
