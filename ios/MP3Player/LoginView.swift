import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var errorMessage: String?
    @State private var showEmailSheet = false
    @State private var showPhoneSheet = false

    var body: some View {
        ZStack {
            Theme.background

            VStack(spacing: 0) {
                Spacer()

                // Brand
                VStack(spacing: 16) {
                    BrandLogoTile(size: 92)

                    Text("Sonus")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)

                    Text("An audio sanctuary")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textSubtle)
                }

                Spacer()

                // Sign-in options
                VStack(spacing: 12) {
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = authManager.prepareAppleSignInRequest()
                        },
                        onCompletion: handleAppleSignIn
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .cornerRadius(14)

                    Button {
                        Task { await authManager.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 19))
                            Text("Continue with Google")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Theme.hairline, lineWidth: 1)
                        )
                    }

                    HStack {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        Text("or")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textSubtle)
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    .padding(.vertical, 6)

                    HStack(spacing: 12) {
                        secondaryOption(icon: "envelope", title: "Email") {
                            showEmailSheet = true
                        }
                        secondaryOption(icon: "iphone", title: "Phone") {
                            showPhoneSheet = true
                        }
                    }
                }
                .padding(.horizontal, 24)

                if let errorMessage {
                    InlineError(message: errorMessage)
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // Legal
                VStack(spacing: 4) {
                    Text("By continuing, you agree to our")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.subtleText)
                    HStack(spacing: 4) {
                        Link("Terms of Service", destination: ConsentConfig.termsURL)
                        Text("·").foregroundColor(Theme.subtleText)
                        Link("Privacy Policy", destination: ConsentConfig.privacyURL)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .padding(.bottom, 32)
            }

            if case .authenticating = authManager.authState {
                Color.black.opacity(0.45).ignoresSafeArea()
                ProgressView().scaleEffect(1.4).tint(Theme.accent)
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showEmailSheet) {
            EmailAuthSheet().environmentObject(authManager)
        }
        .sheet(isPresented: $showPhoneSheet) {
            PhoneAuthSheet(mode: .signIn).environmentObject(authManager)
        }
        .onChange(of: authManager.authState.errorText) { _, newValue in
            errorMessage = newValue
        }
    }

    private func secondaryOption(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            Task { await authManager.authenticateWithApple(authorization: authorization) }
        case .failure(let error):
            authManager.cancelAppleSignIn()
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Apple sign in didn't complete. Please try again."
            }
        }
    }
}

private extension AuthenticationState {
    var errorText: String? {
        if case .error(let error) = self { return error.errorDescription }
        return nil
    }
}

// MARK: - Email sheet

struct EmailAuthSheet: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Picker("", selection: $isSignUp) {
                            Text("Sign In").tag(false)
                            Text("Create Account").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)

                        if isSignUp {
                            ThemedField(label: "First Name", text: $firstName,
                                        placeholder: "First name", contentType: .givenName)
                            ThemedField(label: "Last Name", text: $lastName,
                                        placeholder: "Last name", contentType: .familyName)
                        }

                        ThemedField(label: "Email", text: $email,
                                    placeholder: "you@example.com",
                                    keyboard: .emailAddress, contentType: .emailAddress)

                        ThemedField(label: "Password", text: $password,
                                    placeholder: isSignUp ? "At least 8 characters" : "Password",
                                    isSecure: true,
                                    contentType: isSignUp ? .newPassword : .password)

                        if let errorMessage { InlineError(message: errorMessage) }
                        if let infoMessage {
                            Text(infoMessage)
                                .font(.system(size: 13))
                                .foregroundColor(.green.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }

                        PrimaryButton(
                            title: isSignUp ? "Create Account" : "Sign In",
                            isLoading: isLoading,
                            isDisabled: !formIsValid
                        ) {
                            submit()
                        }
                        .padding(.top, 4)

                        if !isSignUp {
                            Button("Forgot password?") { sendReset() }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.accent)
                                .padding(.top, 4)

                            Text("You can also sign in with a one-time code sent to your phone — use the Phone option on the previous screen.")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.subtleText)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle(isSignUp ? "Create Account" : "Sign In")
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
        let emailOK = email.contains("@") && email.contains(".")
        let passwordOK = password.count >= 8
        let namesOK = !isSignUp || !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        return emailOK && passwordOK && namesOK
    }

    private func submit() {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        Task {
            let error: AuthenticationError?
            if isSignUp {
                error = await authManager.signUp(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password,
                    firstName: firstName.trimmingCharacters(in: .whitespaces),
                    lastName: lastName.trimmingCharacters(in: .whitespaces)
                )
            } else {
                error = await authManager.signIn(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            }
            isLoading = false
            if let error {
                errorMessage = error.errorDescription
            } else {
                dismiss()
            }
        }
    }

    private func sendReset() {
        guard email.contains("@") else {
            errorMessage = "Enter your email above first, then tap Forgot password."
            return
        }
        errorMessage = nil
        Task {
            let error = await authManager.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
            if let error {
                errorMessage = error.errorDescription
            } else {
                infoMessage = "Password reset link sent. Check your inbox."
            }
        }
    }
}

// MARK: - Phone sheet (sign in OR link to existing account)

struct PhoneAuthSheet: View {
    enum Mode {
        case signIn       // login / OTP account recovery
        case linkToAccount // add or change phone from Profile
    }

    let mode: Mode
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var phoneNumber = ""
    @State private var code = ""
    @State private var verificationID: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background

                VStack(spacing: 16) {
                    if verificationID == nil {
                        ThemedField(label: "Phone Number", text: $phoneNumber,
                                    placeholder: "+1 555 123 4567",
                                    keyboard: .phonePad, contentType: .telephoneNumber)

                        Text("Include your country code. We'll text you a one-time code — carrier rates may apply.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.subtleText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let errorMessage { InlineError(message: errorMessage) }

                        PrimaryButton(title: "Send Code",
                                      isLoading: isLoading,
                                      isDisabled: normalizedPhone.count < 8) {
                            sendCode()
                        }
                    } else {
                        ThemedField(label: "Verification Code", text: $code,
                                    placeholder: "6-digit code",
                                    keyboard: .numberPad, contentType: .oneTimeCode)

                        if let errorMessage { InlineError(message: errorMessage) }

                        PrimaryButton(title: mode == .signIn ? "Verify & Sign In" : "Verify & Save",
                                      isLoading: isLoading,
                                      isDisabled: code.count < 6) {
                            verify()
                        }

                        Button("Resend code") {
                            code = ""
                            sendCode()
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.accent)
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle(mode == .signIn ? "Phone Sign In" : "Phone Number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var normalizedPhone: String {
        let cleaned = phoneNumber.filter { $0.isNumber || $0 == "+" }
        return cleaned.hasPrefix("+") ? cleaned : "+" + cleaned
    }

    private func sendCode() {
        errorMessage = nil
        isLoading = true
        Task {
            let result = await authManager.sendPhoneOTP(to: normalizedPhone)
            isLoading = false
            switch result {
            case .success(let id):
                verificationID = id
            case .failure(let error):
                errorMessage = error.errorDescription
            }
        }
    }

    private func verify() {
        guard let verificationID else { return }
        errorMessage = nil
        isLoading = true
        Task {
            let error: AuthenticationError?
            switch mode {
            case .signIn:
                error = await authManager.signInWithOTP(verificationID: verificationID, code: code)
            case .linkToAccount:
                error = await authManager.linkPhone(verificationID: verificationID,
                                                    code: code,
                                                    phoneE164: normalizedPhone)
            }
            isLoading = false
            if let error {
                errorMessage = error.errorDescription
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationManager.shared)
}
