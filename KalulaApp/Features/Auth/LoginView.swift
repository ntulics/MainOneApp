import SwiftUI

// MARK: - LoginView

struct LoginView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        if auth.mfaPending {
            MfaView()
                .environmentObject(auth)
        } else {
            CredentialsView()
                .environmentObject(auth)
        }
    }
}

// MARK: - Credentials step (email + password, passkey button)

private struct CredentialsView: View {
    @EnvironmentObject var auth: AuthService

    @State private var email       = ""
    @State private var password    = ""
    @State private var isLoading   = false
    @State private var errorMessage: String?
    @State private var passkeyLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 48)

                    // Logo
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(hex: "#1366EF"))
                                .frame(width: 72, height: 72)
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        Text("MainOne")
                            .font(.title.bold())
                        Text("Sign in to your account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Fields
                    VStack(spacing: 14) {
                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    // Error
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Sign in button
                    Button {
                        Task { await signIn() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#1366EF"))
                    .padding(.horizontal)
                    .disabled(isLoading || passkeyLoading || email.isEmpty || password.isEmpty)

                    // Divider
                    HStack {
                        Rectangle().frame(height: 1).foregroundStyle(Color(.separator))
                        Text("or").font(.caption).foregroundStyle(.secondary).fixedSize()
                        Rectangle().frame(height: 1).foregroundStyle(Color(.separator))
                    }
                    .padding(.horizontal)

                    // Passkey button
                    Button {
                        Task { await signInWithPasskey() }
                    } label: {
                        HStack(spacing: 10) {
                            if passkeyLoading {
                                ProgressView().tint(.primary)
                            } else {
                                Image(systemName: "person.badge.key.fill")
                                    .font(.system(size: 18))
                            }
                            Text(passkeyLoading ? "Authenticating…" : "Sign in with Passkey")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .padding(.horizontal)
                    .disabled(isLoading || passkeyLoading || email.isEmpty)
                    .overlay(
                        // Subtle hint when email is empty
                        email.isEmpty
                            ? AnyView(Text("Enter your email first")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.top, 58)
                                .padding(.horizontal))
                            : AnyView(EmptyView())
                        , alignment: .top
                    )

                    Spacer().frame(height: 32)
                }
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Actions

    private func signIn() async {
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await auth.login(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
        } catch let e as APIServiceError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithPasskey() async {
        passkeyLoading = true
        errorMessage   = nil
        defer { passkeyLoading = false }

        do {
            try await auth.loginWithPasskey(email: email.trimmingCharacters(in: .whitespaces))
        } catch let e as APIServiceError {
            // Ignore user cancellation silently
            if case .httpError(0, _) = e { return }
            errorMessage = e.errorDescription
        } catch let e as NSError where e.domain == "com.apple.AuthenticationServices.AuthorizationError" {
            // Associated Domains not configured — happens with a free Apple Developer account
            errorMessage = "Passkey sign-in is not available on this device. Please sign in with your email and password."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - MFA step

private struct MfaView: View {
    @EnvironmentObject var auth: AuthService

    @State private var code        = ""
    @State private var isLoading   = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 48)

                    // Icon
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(hex: "#1366EF"))
                                .frame(width: 72, height: 72)
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        Text("Two-Factor Auth")
                            .font(.title.bold())
                        Text("Enter the 6-digit code from your authenticator app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Code field
                    TextField("000000", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .onChange(of: code) { new in
                            // Auto-submit when 6 digits are entered (iOS 16 compatible)
                            let digits = new.filter(\.isNumber)
                            code = String(digits.prefix(6))
                            if code.count == 6 { Task { await verify() } }
                        }

                    // Error
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Verify button
                    Button {
                        Task { await verify() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Verify")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#1366EF"))
                    .padding(.horizontal)
                    .disabled(isLoading || code.count < 6)

                    // Back to login
                    Button {
                        auth.cancelMfa()
                    } label: {
                        Text("Use a different account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer().frame(height: 32)
                }
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            }
            .navigationTitle("")
        }
    }

    private func verify() async {
        guard code.count == 6 else { return }
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await auth.verifyMfa(code: code)
        } catch let e as APIServiceError {
            errorMessage = e.errorDescription
            code = ""
        } catch {
            errorMessage = error.localizedDescription
            code = ""
        }
    }
}

// MARK: - Color+Hex (local helper)

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
