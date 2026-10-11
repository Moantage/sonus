import SwiftUI

/// Changes the password, or sets a first one for accounts that signed in another way.
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
            ScrollView {
                VStack(spacing: 16) {
                    if isSettingFirstPassword {
                        Text("Add a password so you can also sign in with your email.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSubtle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ThemedField(label: "Current password", text: $currentPassword,
                                    placeholder: "Current password",
                                    isSecure: true, contentType: .password)
                    }

                    ThemedField(label: "New password", text: $newPassword,
                                placeholder: "At least 8 characters",
                                isSecure: true, contentType: .newPassword)

                    ThemedField(label: "Confirm new password", text: $confirmPassword,
                                placeholder: "Repeat new password",
                                isSecure: true, contentType: .newPassword)

                    if let errorMessage { InlineError(message: errorMessage) }

                    PrimaryButton(title: isSettingFirstPassword ? "Set password" : "Update password",
                                  isLoading: isLoading,
                                  isDisabled: !formIsValid) {
                        submit()
                    }
                }
                .padding(24)
            }
            .background(Theme.backgroundBase)
            .navigationTitle(isSettingFirstPassword ? "Set password" : "Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.backgroundBase)
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
