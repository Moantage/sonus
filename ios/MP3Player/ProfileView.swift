import SwiftUI

/// Profile & settings, opened from the avatar on any tab: banner, playback settings, music
/// sources, profile banner and sync, account details, security, sign out and account deletion. Everything in Sonus
/// is free; there are no plans or purchases.
struct ProfileView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var librarySync: LibrarySyncService
    @EnvironmentObject private var shell: ShellState

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isEditing = false

    @State private var showChangePassword = false
    @State private var showPhoneSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showBannerPicker = false
    @State private var showPlaybackControls = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ScreenMetrics.sectionSpacing) {
                header
                playbackSection
                MusicSourcesSection()
                profileSection
                accountSection
                securitySection
                signOutSection
            }
            .padding(.horizontal, ScreenMetrics.pageMargin)
            .padding(.bottom, 32)
        }
        .background(Theme.backgroundBase)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackground(Theme.backgroundBase)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Cancel" : "Edit") {
                    if isEditing { loadUserData() }
                    withAnimation(Theme.Motion.snappy) { isEditing.toggle() }
                }
                .font(.body.weight(.semibold))
            }
        }
        .alert("Profile", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes your account and profile data. This cannot be undone.")
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
        }
        .sheet(isPresented: $showPhoneSheet) {
            PhoneAuthSheet(mode: .linkToAccount)
        }
        .sheet(isPresented: $showBannerPicker) {
            BannerPickerSheet()
        }
        .sheet(isPresented: $showPlaybackControls) {
            AdvancedControlsSheet()
        }
        .onAppear {
            loadUserData()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(ProfileBanner.banner(for: authManager.currentUser?.profileBanner).gradient)
                    .frame(height: ScreenMetrics.isCompact ? 104 : 128)

                Button {
                    showBannerPicker = true
                } label: {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.35), in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Change profile banner")
                .padding(4)
            }

            AvatarView(initials: initials, size: ScreenMetrics.isCompact ? 72 : 88)
                .overlay(Circle().stroke(Theme.backgroundBase, lineWidth: 4))
                .padding(.top, ScreenMetrics.isCompact ? -46 : -56)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.system(.title2).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                if !email.isEmpty {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSubtle)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Sections and actions

extension ProfileView {
    // MARK: - Playback

    private var playbackSection: some View {
        SettingsSection(title: "Playback") {
            SettingsRow(icon: "slider.horizontal.3", title: "Playback controls", detail: "Speed, equaliser, skip and sleep timer") {
                showPlaybackControls = true
            }

            Toggle(isOn: Binding(
                get: { player.highQualityAudioEnabled },
                set: { player.setHighQualityAudio($0) }
            )) {
                SettingsLabel(icon: "waveform", title: "High-quality audio", detail: "Best output for AirPlay and Bluetooth")
            }
            .tint(Theme.accent)
            .frame(minHeight: 52)

            SettingsRow(icon: "arrow.down.circle", title: "Downloaded", detail: downloadsDetail) {
                shell.push(.collection(.downloaded))
            }
        }
    }

    private var downloadsDetail: String {
        let downloaded = libraryStore.songs.filter(\.isDownloadedLocally).count
        return downloaded == 1 ? "1 song on this device" : "\(downloaded) songs on this device"
    }

    // MARK: - Profile and sync

    private var profileSection: some View {
        SettingsSection(title: "Profile and sync") {
            SettingsRow(
                icon: "photo",
                title: "Profile banner",
                detail: ProfileBanner.banner(for: authManager.currentUser?.profileBanner).name
            ) {
                showBannerPicker = true
            }

            SettingsRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Sync across devices",
                detail: syncDetail
            ) {
                syncNow()
            }
        }
    }

    private var syncDetail: String {
        switch librarySync.status {
        case .syncing: return "Syncing…"
        case .error: return "Couldn't sync. Tap to retry"
        default:
            if let date = librarySync.lastSyncedAt {
                let formatter = RelativeDateTimeFormatter()
                return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
            }
            return "Tap to sync now"
        }
    }

    private func syncNow() {
        Task {
            await librarySync.push(libraryStore.currentSnapshot())
            if let remote = await librarySync.pull() {
                libraryStore.mergeRemoteSnapshot(remote)
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        SettingsSection(title: "Account") {
            if isEditing {
                VStack(spacing: 14) {
                    ThemedField(label: "First name", text: $firstName, placeholder: "First name", contentType: .givenName)
                    ThemedField(label: "Last name", text: $lastName, placeholder: "Last name", contentType: .familyName)
                    PrimaryButton(
                        title: "Save changes",
                        isLoading: isSaving,
                        isDisabled: firstName.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        saveProfile()
                    }
                }
                .padding(.vertical, 8)
            } else {
                SettingsValueRow(title: "Name", value: displayName == "Your profile" ? "Not provided" : displayName)
            }
            SettingsValueRow(title: "Email", value: email.isEmpty ? "Not provided" : email)
            SettingsValueRow(title: "Member since", value: formattedDate(authManager.currentUser?.createdAt ?? Date()))
            SettingsValueRow(title: "Sign-in methods", value: providerSummary)
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        SettingsSection(title: "Security") {
            SettingsRow(icon: "key", title: authManager.hasPasswordProvider ? "Change password" : "Set a password") {
                showChangePassword = true
            }

            SettingsRow(
                icon: "iphone",
                title: authManager.currentUser?.phoneLast4 != nil
                    ? "Phone ••••\(authManager.currentUser?.phoneLast4 ?? "")"
                    : "Add phone number",
                detail: authManager.currentUser?.phoneLast4 != nil ? "Change" : nil
            ) {
                showPhoneSheet = true
            }
        }
    }

    private var signOutSection: some View {
        VStack(spacing: 12) {
            Button("Sign out") {
                authManager.signOut()
            }
            .buttonStyle(PillButtonStyle(kind: .outline))

            Button("Delete account") {
                showDeleteConfirmation = true
            }
            .font(.system(.subheadline).weight(.semibold))
            .foregroundStyle(Theme.error)
            .frame(minHeight: 44)

            if let deleteError {
                InlineError(message: deleteError)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Logic

    private var initials: String {
        "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
    }

    private var displayName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Your profile" : name
    }

    private var providerSummary: String {
        let names: [String: String] = [
            "password": "Email",
            "google.com": "Google",
            "apple.com": "Apple",
            "phone": "Phone"
        ]
        let list = authManager.linkedProviders.compactMap { names[$0] }
        return list.isEmpty ? "—" : list.joined(separator: ", ")
    }

    private func loadUserData() {
        guard let user = authManager.currentUser else { return }
        firstName = user.firstName
        lastName = user.lastName
        email = user.email
    }

    private func saveProfile() {
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        guard !first.isEmpty else {
            alertMessage = "First name cannot be empty"
            showAlert = true
            return
        }
        isSaving = true
        Task {
            await authManager.updateUserProfile(firstName: first, lastName: last)
            isSaving = false
            isEditing = false
            alertMessage = "Profile updated successfully"
            showAlert = true
        }
    }

    private func deleteAccount() {
        deleteError = nil
        Task {
            if let error = await authManager.deleteAccount() {
                deleteError = error == .requiresRecentLogin
                    ? "For security, sign out and sign back in, then try deleting again."
                    : error.errorDescription
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
