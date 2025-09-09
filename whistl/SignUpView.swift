//
//  SignUpView.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI
import FirebaseAuth

struct SignUpView: View {
    @Environment(AppController.self) private var appController

    @State private var isSecure = true
    @State private var isLoading = false

    // Validation errors
    @State private var nameError: String?
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var globalError: String?

    @FocusState private var focusedField: Field?
    private let brand = BrandPalette()

    enum Field { case name, email, password }

    var body: some View {
        ZStack {
            brand.background()

            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 12)

                    // Header
                    VStack(spacing: 8) {
                        Text("Create your account")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(brand.primaryText)
                        Text("Sign up securely to continue")
                            .font(.callout)
                            .foregroundStyle(brand.secondaryText)
                    }
                    .padding(.top, 16)

                    // Card
                    VStack(spacing: 14) {
                        if let globalError {
                            errorBanner(globalError)
                        }

                        // Name
                        fieldWithLabel(
                            systemImage: "person",
                            title: "Name",
                            text: Bindable(appController).name,
                            isSecure: .constant(false),
                            isPassword: false,
                            isError: nameError != nil
                        )
                        .focused($focusedField, equals: .name)
                        .onSubmit {
                            _ = validateName(false)
                            focusedField = .email
                        }
                        if let nameError {
                            fieldErrorText(nameError)
                        }

                        // Email
                        fieldWithLabel(
                            systemImage: "envelope",
                            title: "Email",
                            text: Bindable(appController).email,
                            isSecure: .constant(false),
                            isPassword: false,
                            isError: emailError != nil
                        )
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .onSubmit {
                            _ = validateEmail(false)
                            focusedField = .password
                        }
                        if let emailError {
                            fieldErrorText(emailError)
                        }

                        // Password
                        fieldWithLabel(
                            systemImage: "lock",
                            title: "Password",
                            text: Bindable(appController).password,
                            isSecure: $isSecure,
                            isPassword: true,
                            isError: passwordError != nil
                        )
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            _ = validatePassword(false)
                            signUp()
                        }
                        if let passwordError {
                            fieldErrorText(passwordError)
                        } else {
                            Text("Use at least 6 characters.")
                                .font(.caption)
                                .foregroundStyle(brand.secondaryText)
                        }

                        Button(action: signUp) {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                }
                                Text("Create account")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(primaryButtonStyle())
                        .disabled(!isFormValid || isLoading)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: brand.cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: brand.cornerRadius, style: .continuous)
                            .strokeBorder(brand.cardStroke, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 8)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("Sign up")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            focusedField = .name
        }
        .onChange(of: appController.name) { _ in if nameError != nil { _ = validateName(true) } }
        .onChange(of: appController.email) { _ in if emailError != nil { _ = validateEmail(true) } }
        .onChange(of: appController.password) { _ in if passwordError != nil { _ = validatePassword(true) } }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        validateName(true) && validateEmail(true) && validatePassword(true)
    }

    @discardableResult
    private func validateName(_ silent: Bool) -> Bool {
        let name = appController.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = !name.isEmpty
        if !silent { nameError = ok ? nil : "Enter your name." }
        else if nameError != nil { nameError = ok ? nil : nameError }
        return ok
    }

    @discardableResult
    private func validateEmail(_ silent: Bool) -> Bool {
        let email = appController.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = email.range(of: #"^\S+@\S+\.\S+$"#, options: .regularExpression) != nil
        if !silent { emailError = ok ? nil : "Enter a valid email address." }
        else if emailError != nil { emailError = ok ? nil : emailError }
        return ok
    }

    @discardableResult
    private func validatePassword(_ silent: Bool) -> Bool {
        let ok = appController.password.count >= 6
        if !silent { passwordError = ok ? nil : "Password must be at least 6 characters." }
        else if passwordError != nil { passwordError = ok ? nil : passwordError }
        return ok
    }

    // MARK: - Actions

    private func signUp() {
        clearErrors()
        guard isFormValid, !isLoading else {
            if !validateName(false) { focusedField = .name }
            else if !validateEmail(false) { focusedField = .email }
            else if !validatePassword(false) { focusedField = .password }
            return
        }

        isLoading = true
        Task {
            do {
                try await appController.signUp()
                try await appController.updateDisplayName(appController.name)
                // After sign-up, AppController updates authState to authenticated via listener.
                // ContentView will route to PairingGateView if not paired.
            } catch {
                handleAuthError(error)
            }
            isLoading = false
        }
    }

    private func handleAuthError(_ error: Error) {
        let nsError = error as NSError
        if let authCode = AuthErrorCode(_bridgedNSError: nsError) {
            switch authCode.code {
            case .emailAlreadyInUse:
                emailError = "That email is already in use."
            case .invalidEmail:
                emailError = "Enter a valid email address."
            case .weakPassword:
                passwordError = "Password must be at least 6 characters."
            default:
                globalError = nsError.localizedDescription
            }
        } else {
            globalError = nsError.localizedDescription
        }
    }

    private func clearErrors() {
        withAnimation {
            nameError = nil
            emailError = nil
            passwordError = nil
            globalError = nil
        }
    }

    // MARK: - Small UI helpers (local, to avoid cross-file private types)

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(brand.error)
            Text(message)
                .font(.footnote)
                .foregroundStyle(brand.primaryText)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(brand.error.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(brand.error.opacity(0.25), lineWidth: 1)
        )
    }

    private func fieldErrorText(_ message: String) -> some View {
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

    private func fieldWithLabel(systemImage: String,
                                title: String,
                                text: Binding<String>,
                                isSecure: Binding<Bool>,
                                isPassword: Bool,
                                isError: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(brand.accent)
                .imageScale(.medium)

            Group {
                if isPassword, isSecure.wrappedValue {
                    SecureField(title, text: text)
                        .foregroundStyle(brand.primaryText)
                } else {
                    TextField(title, text: text)
                        .foregroundStyle(brand.primaryText)
                }
            }

            if isPassword {
                Button(action: { isSecure.wrappedValue.toggle() }) {
                    Image(systemName: isSecure.wrappedValue ? "eye.slash" : "eye")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSecure.wrappedValue ? "Show password" : "Hide password")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: brand.fieldCornerRadius, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: brand.fieldCornerRadius, style: .continuous)
                .stroke(isError ? brand.error : brand.cardStroke, lineWidth: isError ? 1.5 : 1)
        )
    }

    private func primaryButtonStyle() -> some ButtonStyle {
        BorderedProminentButtonStyle()
    }
}

#Preview {
    NavigationStack { SignUpView() }.environment(AppController())
}
