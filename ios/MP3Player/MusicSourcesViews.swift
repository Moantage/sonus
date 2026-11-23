import SonusCore
import SwiftUI

/// Connects an OpenSubsonic server (Navidrome, Gonic, Ampache, ...): address, username, password.
///
/// Nothing is saved until the server answers and its library is listed. The password goes only to
/// the Keychain; requests carry a salted token instead.
struct ConnectServerSheet: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject private var sources = SourceStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        CompatNavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Connect Navidrome, Gonic, Ampache or any other Subsonic-compatible server.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ThemedField(label: "Server address", text: $address,
                                placeholder: "music.example.com or 192.168.1.20:4533",
                                keyboard: .URL, contentType: .URL)
                    ThemedField(label: "Username", text: $username, placeholder: "Username",
                                contentType: .username)
                    ThemedField(label: "Password", text: $password, placeholder: "Password",
                                isSecure: true, contentType: .password)

                    if let errorMessage {
                        InlineError(message: errorMessage)
                    }

                    PrimaryButton(title: "Connect", isLoading: isConnecting, isDisabled: !formIsValid) {
                        connect()
                    }

                    Text("Sonus signs in with a one-time token, so your password isn't sent with each "
                         + "request. It stays in this iPhone's Keychain. Servers on the internet need https.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
            .background(Theme.backgroundBase)
            .navigationTitle("Music server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .emberSheet(background: Theme.backgroundBase)
        .interactiveDismissDisabled(isConnecting)
    }

    private var formIsValid: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    private func connect() {
        errorMessage = nil
        guard let serverURL = OpenSubsonicEndpoints.serverURL(from: address) else {
            errorMessage = "Enter the server's address, like music.example.com or 192.168.1.20:4533."
            return
        }
        guard NetworkPolicy.allows(serverURL) else {
            errorMessage = "Servers on the internet must use https. Plain http works only on your home network."
            return
        }
        let credentials = OpenSubsonicCredentials(
            username: username.trimmingCharacters(in: .whitespaces),
            password: password
        )
        isConnecting = true
        Task {
            do {
                try await sources.addOpenSubsonicSource(serverURL: serverURL, credentials: credentials, into: libraryStore)
                isConnecting = false
                dismiss()
            } catch {
                isConnecting = false
                errorMessage = SourceStore.message(for: error)
            }
        }
    }
}

/// Profile's list of connected sources, with refresh and remove.
struct MusicSourcesSection: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject private var sources = SourceStore.shared

    @State private var isConnectPresented = false
    @State private var pendingRemoval: MusicSource?

    var body: some View {
        SettingsSection(title: "Music sources") {
            ForEach(sources.sources) { source in
                Menu {
                    Button { refresh(source) } label: {
                        Label("Refresh now", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) { pendingRemoval = source } label: {
                        Label("Remove…", systemImage: "trash")
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsLabel(icon: icon(for: source), title: source.name, detail: detail(for: source))
                        Spacer(minLength: 0)
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Refresh or remove this source")
            }
            SettingsRow(icon: "plus.circle", title: "Connect a music server",
                        detail: "Navidrome, Gonic, Ampache and other Subsonic servers") {
                isConnectPresented = true
            }
        }
        .sheet(isPresented: $isConnectPresented) {
            ConnectServerSheet()
        }
        .alert(
            "Remove \(pendingRemoval?.name ?? "source")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let source = pendingRemoval {
                    sources.removeSource(source.id, from: libraryStore)
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its \(pendingRemoval.map(songCount) ?? "songs") leave your library, downloads included. "
                 + "Nothing changes on the server.")
        }
    }

    private func refresh(_ source: MusicSource) {
        Task { _ = try? await sources.refresh(source.id, into: libraryStore) }
    }

    private func icon(for source: MusicSource) -> String {
        switch source.kind {
        case .openSubsonic, .sonusServer: "server.rack"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .manifest: "doc.text"
        }
    }

    private func songCount(_ source: MusicSource) -> String {
        let count = libraryStore.songs(fromSource: source.id).count
        return count == 1 ? "1 song" : "\(count) songs"
    }

    private func detail(for source: MusicSource) -> String {
        switch sources.refreshStates[source.id] ?? .idle {
        case .refreshing:
            return "Refreshing…"
        case .failed(let message):
            return message
        case .succeeded(_, _, let warnings) where !warnings.isEmpty:
            return "\(songCount(source)) · \(warnings[0])"
        case .idle, .succeeded:
            guard let date = source.lastRefreshedAt else { return songCount(source) }
            let relative = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
            return "\(songCount(source)) · Updated \(relative)"
        }
    }
}
