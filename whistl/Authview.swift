//
//  Authview.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI
import FirebaseAuth

struct Authview: View {

    @Environment(AppController.self) private var appController

    @State private var isSignUp = false
    @State private var isSecure = true
    @State private var isLoading = false

    // Error presentation
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var globalError: String?

    // Success toast
    @State private var toastMessage: String?
    @State private var showToast = false

    // Reset password sheet
    @State private var showReset = false
    @State private var resetEmail: String = ""
    @State private var resetState: ResetState = .idle

    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    enum ResetState {
        case idle
        case sending
        case sent(message: String)
        case failed(message: String)
    }

    // Brand colors
    private let brand = Brand()

    var body: some View {
        ZStack {
            BackgroundGradient(brand: brand)

            VStack(spacing: 24) {
                Spacer(minLength: 12)

                HeaderView(isSignUp: isSignUp, brand: brand)

                CardView(
                    isSignUp: $isSignUp,
                    isSecure: $isSecure,
                    isLoading: $isLoading,
                    emailError: $emailError,
                    passwordError: $passwordError,
                    globalError: $globalError,
                    brand: brand,
                    email: Bindable(appController).email,
                    password: Bindable(appController).password,
                    onPrimary: authenticate,
                    onToggleMode: { isSignUp.toggle(); clearErrors() },
                    onForgot: {
                        showReset = true
                        resetEmail = appController.email
                        clearErrors()
                    },
                    validateEmail: validateEmail,
                    validatePassword: validatePassword
                )
                .padding(.horizontal, 20)

                Spacer()

                FooterView(brand: brand)
            }

            ToastContainer(
                showToast: $showToast,
                toastMessage: toastMessage,
                brand: brand
            )
        }
        .navigationTitle("whistl")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("whistl")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(brand.accent)
                    .accessibilityHidden(true)
            }
        }
        .tint(brand.accent)
        .sheet(isPresented: $showReset) {
            ResetPasswordSheet(
                email: $resetEmail,
                state: $resetState,
                brand: brand,
                onSend: sendPasswordReset
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            // Initial focus for better flow
            focusedField = appController.email.isEmpty ? .email : .password
        }
        .onChange(of: appController.email) { _ in
            if emailError != nil { validateEmail() }
        }
        .onChange(of: appController.password) { _ in
            if passwordError != nil { validatePassword() }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        validateEmail(silent: true) && validatePassword(silent: true)
    }

    @discardableResult
    private func validateEmail(silent: Bool = false) -> Bool {
        let email = appController.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = isValidEmail(email)
        if !silent {
            emailError = isValid ? nil : "Enter a valid email address."
        } else if emailError != nil {
            emailError = isValid ? nil : emailError
        }
        return isValid
    }

    @discardableResult
    private func validatePassword(silent: Bool = false) -> Bool {
        let pass = appController.password
        let isValid = pass.count >= 6
        if !silent {
            passwordError = isValid ? nil : "Password must be at least 6 characters."
        } else if passwordError != nil {
            passwordError = isValid ? nil : passwordError
        }
        return isValid
    }

    private func isValidEmail(_ email: String) -> Bool {
        // Simple RFC-like pattern sufficient for UI validation
        let pattern = #"^\S+@\S+\.\S+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private func clearErrors() {
        withAnimation {
            emailError = nil
            passwordError = nil
            globalError = nil
        }
    }

    // MARK: - Actions

    private func authenticate() {
        clearErrors()
        guard isFormValid, !isLoading else {
            if !validateEmail(silent: false) { focusedField = .email }
            else if !validatePassword(silent: false) { focusedField = .password }
            return
        }
        isLoading = true
        Task {
            do {
                if isSignUp {
                    try await appController.signUp()
                    showSuccessToast("Account created. Welcome to whistl!")
                } else {
                    try await appController.signIn()
                    showSuccessToast("Signed in successfully.")
                }
            } catch {
                handleAuthError(error)
            }
            isLoading = false
        }
    }

    private func handleAuthError(_ error: Error) {
        let nsError = error as NSError
        if let authCode = AuthErrorCode(_bridgedNSError: nsError) {
            let code = authCode.code
            var message: String = nsError.localizedDescription

            switch code {
            case .emailAlreadyInUse:
                message = "That email is already in use. Try signing in or use a different email."
                emailError = message
                focusedField = .email
            case .invalidEmail:
                message = "Enter a valid email address."
                emailError = message
                focusedField = .email
            case .weakPassword:
                message = "Password must be at least 6 characters."
                passwordError = message
                focusedField = .password
            case .wrongPassword:
                message = "Incorrect password. Please try again."
                passwordError = message
                focusedField = .password
            case .userNotFound:
                message = "No account found for that email."
                emailError = message
                focusedField = .email
            case .networkError:
                message = "Network error. Check your connection and try again."
                globalError = message
            default:
                globalError = message
            }
        } else {
            // Not a FirebaseAuth error; show generic message
            globalError = nsError.localizedDescription
        }
    }

    private func showSuccessToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showToast = true
        }
    }

    private func sendPasswordReset() {
        guard !resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard isValidEmail(resetEmail) else {
            resetState = .failed(message: "Enter a valid email address.")
            return
        }
        resetState = .sending
        Task {
            do {
                try await Auth.auth().sendPasswordReset(withEmail: resetEmail)
                let message = "We’ve sent a reset link to \(resetEmail). Check your inbox."
                resetState = .sent(message: message)
                showSuccessToast("Password reset email sent.")
            } catch {
                let nsError = error as NSError
                if let authCode = AuthErrorCode(_bridgedNSError: nsError) {
                    switch authCode.code {
                    case .invalidEmail:
                        resetState = .failed(message: "Enter a valid email address.")
                    case .userNotFound:
                        resetState = .failed(message: "No account found for that email.")
                    default:
                        resetState = .failed(message: nsError.localizedDescription)
                    }
                } else {
                    resetState = .failed(message: nsError.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Background

private struct BackgroundGradient: View {
    let brand: Brand
    var body: some View {
        LinearGradient(
            colors: [
                brand.backgroundTop,
                brand.backgroundBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Header

private struct HeaderView: View {
    let isSignUp: Bool
    let brand: Brand

    var body: some View {
        VStack(spacing: 8) {
            LogoView(brand: brand)
            Text(isSignUp ? "Create your account" : "Welcome back")
                .font(.title2.weight(.semibold))
                .foregroundStyle(brand.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("Sign in securely to continue")
                .font(.callout)
                .foregroundStyle(brand.secondaryText)
        }
        .padding(.top, 24)
    }
}

// MARK: - Card

private struct CardView: View {
    @Binding var isSignUp: Bool
    @Binding var isSecure: Bool
    @Binding var isLoading: Bool

    @Binding var emailError: String?
    @Binding var passwordError: String?
    @Binding var globalError: String?

    @FocusState<Authview.Field?> var focusedField: Authview.Field?

    let brand: Brand

    @Binding var email: String
    @Binding var password: String

    var onPrimary: () -> Void
    var onToggleMode: () -> Void
    var onForgot: () -> Void

    var validateEmail: (_ silent: Bool) -> Bool
    var validatePassword: (_ silent: Bool) -> Bool

    var body: some View {
        VStack(spacing: 14) {
            if let globalError {
                GlobalErrorBanner(message: globalError, brand: brand)
            }

            EmailField(
                text: $email,
                isError: emailError != nil,
                brand: brand
            )
            .focused($focusedField, equals: .email)
            .onSubmit {
                _ = validateEmail(false)
                focusedField = .password
            }

            if let emailError {
                FieldErrorText(message: emailError, brand: brand)
            }

            PasswordField(
                text: $password,
                isSecure: $isSecure,
                isError: passwordError != nil,
                isSignUp: isSignUp,
                brand: brand
            )
            .focused($focusedField, equals: .password)
            .onSubmit {
                _ = validatePassword(false)
                onPrimary()
            }

            if let passwordError {
                FieldErrorText(message: passwordError, brand: brand)
            } else if isSignUp {
                Text("Use at least 6 characters.")
                    .font(.caption)
                    .foregroundStyle(brand.secondaryText)
            }

            Button(action: onPrimary) {
                HStack {
                    if isLoading {
                        ProgressView().tint(.white)
                    }
                    Text(isSignUp ? "Create account" : "Sign in")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(brand: brand))
            .disabled(!isFormValid || isLoading)

            HStack {
                Button(action: onToggleMode) {
                    Text(isSignUp ? "I already have an account" : "I don’t have an account")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .tint(brand.accent)

                Spacer()

                Button(action: onForgot) {
                    Text("Forgot password?")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(brand.secondaryText)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(brand.cardStroke, lineWidth: 1)
        )
    }

    private var isFormValid: Bool {
        validateEmail(true) && validatePassword(true)
    }
}

private struct GlobalErrorBanner: View {
    let message: String
    let brand: Brand
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(brand.accent)
            Text(message)
                .font(.footnote)
                .foregroundStyle(brand.primaryText)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(brand.accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(brand.accent.opacity(0.25), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct EmailField: View {
    @Binding var text: String
    var isError: Bool
    let brand: Brand

    var body: some View {
        IconTextField(
            title: "Email",
            systemImage: "envelope",
            text: $text,
            brand: brand,
            isError: isError
        )
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.next)
    }
}

private struct PasswordField: View {
    @Binding var text: String
    @Binding var isSecure: Bool
    var isError: Bool
    var isSignUp: Bool
    let brand: Brand

    var body: some View {
        IconSecureField(
            title: "Password",
            systemImage: "lock",
            text: $text,
            isSecure: $isSecure,
            brand: brand,
            isError: isError
        )
        .textContentType(isSignUp ? .newPassword : .password)
        .submitLabel(.go)
    }
}

// MARK: - Footer

private struct FooterView: View {
    let brand: Brand
    var body: some View {
        Text("By continuing you agree to our Terms & Privacy Policy.")
            .font(.caption)
            .foregroundStyle(brand.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.bottom, 12)
    }
}

// MARK: - Toast Container

private struct ToastContainer: View {
    @Binding var showToast: Bool
    let toastMessage: String?
    let brand: Brand

    var body: some View {
        Group {
            if showToast, let toastMessage {
                ToastView(message: toastMessage, brand: brand)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
                    .padding(.bottom, 24)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.easeInOut) {
                                showToast = false
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

// MARK: - Brand

private struct Brand {
    // Light blue accent and clean white/blue surfaces
    let accent = Color(red: 0.12, green: 0.49, blue: 0.98) // iOS-like blue but softer
    let backgroundTop = Color(red: 0.93, green: 0.97, blue: 1.0) // very light blue
    let backgroundBottom = Color.white
    let primaryText = Color.primary
    let secondaryText = Color.secondary
    let cardStroke = Color.black.opacity(0.06)
    let fieldBackground = Color(.secondarySystemBackground)
    let error = Color.red
}

// MARK: - Logo

private struct LogoView: View {
    let brand: Brand
    var body: some View {
        let gradient = LinearGradient(
            colors: [
                brand.accent,
                brand.accent.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        Text("whistl")
            .font(.system(size: 44, weight: .heavy, design: .rounded))
            .kerning(1.0)
            .foregroundStyle(gradient)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .accessibilityLabel("whistl")
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Components

private struct IconTextField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    let brand: Brand
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(brand.accent)
                .imageScale(.medium)

            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isError ? brand.error : brand.cardStroke, lineWidth: isError ? 1.5 : 1)
        )
    }
}

private struct IconSecureField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    @Binding var isSecure: Bool
    let brand: Brand
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(brand.accent)
                .imageScale(.medium)

            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }

            Button(action: { isSecure.toggle() }) {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSecure ? "Show password" : "Hide password")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isError ? brand.error : brand.cardStroke, lineWidth: isError ? 1.5 : 1)
        )
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let brand: Brand
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                brand.accent,
                                brand.accent.opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.995 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct FieldErrorText: View {
    let message: String
    let brand: Brand
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.small)
                .foregroundStyle(brand.error)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
        .accessibilityHint(message)
    }
}

// MARK: - Toast

private struct ToastView: View {
    let message: String
    let brand: Brand

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text(message)
                .foregroundStyle(.white)
                .font(.subheadline)
                .lineLimit(2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(brand.accent)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 6)
        .padding(.horizontal, 24)
    }
}

// MARK: - Reset Password Sheet

private struct ResetPasswordSheet: View {
    @Binding var email: String
    @Binding var state: Authview.ResetState
    let brand: Brand
    var onSend: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Reset your password")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Enter the email associated with your account and we’ll send you a reset link.")
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                IconTextField(title: "Email", systemImage: "envelope", text: $email, brand: brand)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)

                switch state {
                case .idle:
                    EmptyView()
                case .sending:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Sending reset email…")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(brand.secondaryText)
                case .sent(let message):
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(brand.error)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    onSend()
                } label: {
                    Text("Send reset link")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(PrimaryButtonStyle(brand: brand))
                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Password reset")
            .navigationBarTitleDisplayMode(.inline)
            .tint(brand.accent)
        }
    }

    private var isSending: Bool {
        if case .sending = state { return true }
        return false
    }
}

#Preview {
    Authview()
        .environment(AppController())
}
