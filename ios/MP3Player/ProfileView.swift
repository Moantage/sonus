import SwiftUI

/// Profile & settings, opened from the avatar on any tab: banner and plan, playback settings,
/// Premium features, account details, security, sign out and account deletion.
struct ProfileView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var store: StoreManager
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
    @State private var showPaywall = false
    @State private var showBannerPicker = false
    @State private var showPlaybackControls = false
    @State private var deleteError: String?

    /// Premium if either the verified StoreKit entitlement or the server-set Firestore flag is true.
    private var isPremium: Bool {
        store.isPremium || authManager.currentUser?.isPremium == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if !isPremium {
                    upgradeCard
                }

                playbackSection
                premiumSection
                accountSection
                securitySection
                signOutSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.backgroundBase)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.backgroundBase, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Cancel" : "Edit") {
                    if isEditing { loadUserData() }
                    withAnimation(.snappy) { isEditing.toggle() }
                }
                .fontWeight(.semibold)
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showBannerPicker) {
            BannerPickerSheet(isPremium: isPremium) {
                showBannerPicker = false
                showPaywall = true
            }
        }
        .sheet(isPresented: $showPlaybackControls) {
            AdvancedControlsSheet()
        }
        .onAppear { loadUserData() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(ProfileBanner.banner(for: authManager.currentUser?.profileBanner).gradient)
                    .frame(height: 128)

                Button {
                    if isPremium { showBannerPicker = true } else { showPaywall = true }
                } label: {
                    Image(systemName: isPremium ? "paintbrush.fill" : "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.35), in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(isPremium ? "Change profile banner" : "Profile banners are a Premium feature")
                .padding(4)
            }

            AvatarView(initials: initials, size: 88)
                .overlay(Circle().stroke(Theme.backgroundBase, lineWidth: 4))
                .padding(.top, -56)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if !email.isEmpty {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSubtle)
                }
            }
            .multilineTextAlignment(.center)

            if isPremium {
                Label(store.hasLifetime ? "Premium · Lifetime" : "Premium", systemImage: "crown.fill")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.premiumGold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.premiumGoldWell, in: Capsule())
            } else {
                Text("Free plan")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textSubtle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var upgradeCard: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 44, height: 44)
                    .background(Theme.playGradient, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Go Premium")
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Profile banners, sync across devices and no ads")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSubtle)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(16)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }
}

// MARK: - Sections and actions

extension ProfileView {
    // MARK: - Playback (free)

    private var playbackSection: some View {
        SettingsSection(title: "Playback") {
            Toggle(isOn: Binding(
                get: { player.highQualityAudioEnabled },
                set: { player.setHighQualityAudio($0) }
            )) {
                SettingsLabel(icon: "waveform", title: "High-quality audio", detail: "Best output for AirPlay and Bluetooth")
            }
            .tint(Theme.accent)
            .frame(minHeight: 52)

            SettingsRow(icon: "slider.horizontal.3", title: "Playback controls", detail: "Speed, skip and sleep timer") {
                showPlaybackControls = true
            }

            SettingsRow(icon: "arrow.down.circle", title: "Downloaded", detail: downloadsDetail) {
                shell.push(.collection(.downloaded))
            }
        }
    }

    private var downloadsDetail: String {
        let downloaded = libraryStore.songs.filter(\.isDownloadedLocally).count
        return downloaded == 1 ? "1 song on this device" : "\(downloaded) songs on this device"
    }

    // MARK: - Premium

    private var premiumSection: some View {
        SettingsSection(title: "Premium") {
            SettingsRow(
                icon: "photo",
                title: "Profile banner",
                detail: ProfileBanner.banner(for: authManager.currentUser?.profileBanner).name,
                isLocked: !isPremium
            ) {
                if isPremium { showBannerPicker = true } else { showPaywall = true }
            }

            SettingsRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Sync across devices",
                detail: isPremium ? syncDetail : "Your library on every device",
                isLocked: !isPremium
            ) {
                if isPremium { syncNow() } else { showPaywall = true }
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
            .font(.system(.subheadline, weight: .semibold))
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
