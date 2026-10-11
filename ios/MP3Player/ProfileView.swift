import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var librarySync: LibrarySyncService
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
    @State private var deleteError: String?

    /// Premium if either the verified StoreKit entitlement or the server-set
    /// Firestore flag is true.
    private var isPremium: Bool {
        store.isPremium || authManager.currentUser?.isPremium == true
    }

    var body: some View {
        ZStack {
            Theme.background

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("You")
                        .font(Theme.serif(34))
                        .foregroundColor(Theme.textPrimary)

                    Spacer()

                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                            loadUserData()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.accent)
                    } else {
                        Button {
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
                .padding()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Banner header + avatar + premium badge
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(ProfileBanner.banner(for: authManager.currentUser?.profileBanner).gradient)
                                    .frame(height: 132)

                                Circle()
                                    .fill(Color.black.opacity(0.28))
                                    .frame(width: 88, height: 88)
                                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 2))
                                    .overlay(
                                        Text(initials)
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                            }
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    if isPremium { showBannerPicker = true } else { showPaywall = true }
                                } label: {
                                    Image(systemName: isPremium ? "paintbrush.fill" : "lock.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Circle().fill(Color.black.opacity(0.3)))
                                }
                                .padding(10)
                            }

                            if isPremium {
                                Label(store.hasLifetime ? "Premium · Lifetime" : "Premium", systemImage: "crown.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.premiumGold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Theme.premiumGoldWell))
                            } else {
                                Text("Free plan")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.textSubtle)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.top, 12)

                        // Upgrade CTA (non-premium only)
                        if !isPremium {
                            upgradeCard
                                .padding(.horizontal)
                        }

                        // Premium features
                        premiumSection

                        // Identity
                        VStack(spacing: 12) {
                            infoRow(label: "Email", value: email.isEmpty ? "Not provided" : email)

                            if isEditing {
                                ThemedField(label: "First Name", text: $firstName, placeholder: "First name")
                                ThemedField(label: "Last Name", text: $lastName, placeholder: "Last name")

                                PrimaryButton(title: "Save Changes",
                                              isLoading: isSaving,
                                              isDisabled: firstName.trimmingCharacters(in: .whitespaces).isEmpty) {
                                    saveProfile()
                                }
                            } else {
                                infoRow(label: "First Name", value: firstName.isEmpty ? "Not provided" : firstName)
                                infoRow(label: "Last Name", value: lastName.isEmpty ? "Not provided" : lastName)
                            }
                        }
                        .padding(.horizontal)

                        // Security
                        section(title: "Security") {
                            if authManager.hasPasswordProvider {
                                actionRow(icon: "key", title: "Change Password") {
                                    showChangePassword = true
                                }
                            } else {
                                actionRow(icon: "key", title: "Set a Password") {
                                    showChangePassword = true
                                }
                            }

                            Divider().background(Theme.hairline)

                            actionRow(
                                icon: "iphone",
                                title: authManager.currentUser?.phoneLast4 != nil
                                    ? "Phone ••••\(authManager.currentUser?.phoneLast4 ?? "")"
                                    : "Add Phone Number",
                                detail: authManager.currentUser?.phoneLast4 != nil ? "Change" : nil
                            ) {
                                showPhoneSheet = true
                            }
                        }

                        // Account info
                        section(title: "Account") {
                            HStack {
                                Text("Member Since").foregroundColor(Theme.textSubtle)
                                Spacer()
                                Text(formattedDate(authManager.currentUser?.createdAt ?? Date()))
                                    .foregroundColor(Theme.textPrimary)
                            }
                            .font(.system(size: 15))

                            Divider().background(Theme.hairline)

                            HStack {
                                Text("Sign-in Methods").foregroundColor(Theme.textSubtle)
                                Spacer()
                                Text(providerSummary)
                                    .foregroundColor(Theme.textPrimary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.system(size: 15))
                        }

                        // Danger zone
                        VStack(spacing: 12) {
                            Button {
                                authManager.signOut()
                            } label: {
                                Text("Sign Out")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .emberCard(cornerRadius: 2)
                            }

                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                Text("Delete Account")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.red.opacity(0.9))
                            }

                            if let deleteError {
                                InlineError(message: deleteError)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .alert("Profile", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog("Delete your account?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes your account and profile data. This cannot be undone.")
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet().environmentObject(authManager)
        }
        .sheet(isPresented: $showPhoneSheet) {
            PhoneAuthSheet(mode: .linkToAccount).environmentObject(authManager)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(store)
        }
        .sheet(isPresented: $showBannerPicker) {
            BannerPickerSheet(isPremium: isPremium) { showBannerPicker = false; showPaywall = true }
                .environmentObject(authManager)
        }
        .onAppear { loadUserData() }
    }

    // MARK: - Premium section

    private var premiumSection: some View {
        section(title: "Premium") {
            // High-quality audio output
            premiumRow(icon: "waveform", title: "High-Quality Audio",
                       detail: player.highQualityAudioEnabled ? "On" : "Off",
                       showToggle: true, toggleOn: player.highQualityAudioEnabled) {
                if isPremium {
                    player.setHighQualityAudio(!player.highQualityAudioEnabled)
                } else {
                    showPaywall = true
                }
            }

            Divider().background(Theme.hairline)

            // Profile banner
            premiumRow(icon: "paintbrush", title: "Profile Banner",
                       detail: ProfileBanner.banner(for: authManager.currentUser?.profileBanner).name) {
                if isPremium { showBannerPicker = true } else { showPaywall = true }
            }

            Divider().background(Theme.hairline)

            // Cloud sync
            premiumRow(icon: "arrow.triangle.2.circlepath", title: "Cloud Library Sync",
                       detail: syncDetail) {
                if isPremium { syncNow() } else { showPaywall = true }
            }

            Divider().background(Theme.hairline)

            // Offline downloads status
            premiumRow(icon: "arrow.down.circle", title: "Offline Downloads",
                       detail: downloadsDetail) {
                if !isPremium { showPaywall = true }
            }
        }
    }

    private func premiumRow(icon: String, title: String, detail: String,
                            showToggle: Bool = false, toggleOn: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(isPremium ? Theme.accent : Theme.textSubtle)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if isPremium {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSubtle)
                    if showToggle {
                        Image(systemName: toggleOn ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(toggleOn ? Theme.accent : Theme.textSubtle)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.subtleText)
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.subtleText)
                }
            }
        }
    }

    private var syncDetail: String {
        switch librarySync.status {
        case .syncing: return "Syncing…"
        case .error: return "Retry"
        default:
            if let date = librarySync.lastSyncedAt {
                let f = RelativeDateTimeFormatter()
                return "Synced \(f.localizedString(for: date, relativeTo: Date()))"
            }
            return "Sync now"
        }
    }

    private var downloadsDetail: String {
        let downloaded = libraryStore.songs.filter { $0.isDownloadedLocally }.count
        return "\(downloaded) on device"
    }

    private func syncNow() {
        Task {
            await librarySync.push(libraryStore.currentSnapshot())
            if let remote = await librarySync.pull() {
                libraryStore.mergeRemoteSnapshot(remote)
            }
        }
    }

    // MARK: - Subviews

    private var upgradeCard: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.artworkGradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.accentInk)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Upgrade to Premium")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("No ads, higher quality, sync & offline")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSubtle)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(Theme.mono(9, weight: .regular))
                .tracking(1.5)
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 4)

            VStack(spacing: 12) { content() }
                .padding()
                .emberCard(cornerRadius: 2)
        }
        .padding(.horizontal)
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(Theme.mono(9, weight: .regular))
                .tracking(1.4)
                .foregroundColor(Theme.accent)
            Text(value)
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .emberCard(cornerRadius: 2)
    }

    private func actionRow(icon: String, title: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.accent)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSubtle)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSubtle)
            }
        }
    }

    // MARK: - Logic

    private var initials: String {
        "\(firstName.prefix(1))\(lastName.prefix(1))".uppercased()
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

// MARK: - Change / set password

struct ChangePasswordSheet: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isSettingFirstPassword: Bool { !authManager.hasPasswordProvider }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background

                VStack(spacing: 16) {
                    if isSettingFirstPassword {
                        Text("Add a password so you can also sign in with your email.")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.subtleText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ThemedField(label: "Current Password", text: $currentPassword,
                                    placeholder: "Current password",
                                    isSecure: true, contentType: .password)
                    }

                    ThemedField(label: "New Password", text: $newPassword,
                                placeholder: "At least 8 characters",
                                isSecure: true, contentType: .newPassword)

                    ThemedField(label: "Confirm New Password", text: $confirmPassword,
                                placeholder: "Repeat new password",
                                isSecure: true, contentType: .newPassword)

                    if let errorMessage { InlineError(message: errorMessage) }

                    PrimaryButton(title: isSettingFirstPassword ? "Set Password" : "Update Password",
                                  isLoading: isLoading,
                                  isDisabled: !formIsValid) {
                        submit()
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle(isSettingFirstPassword ? "Set Password" : "Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var formIsValid: Bool {
        let currentOK = isSettingFirstPassword || !currentPassword.isEmpty
        return currentOK && newPassword.count >= 8 && newPassword == confirmPassword
    }

    private func submit() {
        errorMessage = nil
        isLoading = true
        Task {
            let error: AuthenticationError?
            if isSettingFirstPassword {
                error = await authManager.setPassword(new: newPassword)
            } else {
                error = await authManager.changePassword(current: currentPassword, new: newPassword)
            }
            isLoading = false
            if let error {
                errorMessage = error == .requiresRecentLogin
                    ? "For security, sign out and back in, then try again."
                    : error.errorDescription
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(StoreManager.shared)
        .environmentObject(AudioPlayerManager())
        .environmentObject(LibraryStore())
        .environmentObject(LibrarySyncService())
}
