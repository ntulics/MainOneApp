import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var serverURL = "http://localhost:3001/v1"
    @State private var showServerURL = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 40)

                    // Logo / branding
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.orange)
                        Text("Kalula")
                            .font(.largeTitle.bold())
                        Text("Sign in to your account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Fields
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)

                        if showServerURL {
                            TextField("Server URL", text: $serverURL)
                                .autocapitalization(.none)
                                .keyboardType(.URL)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal)

                    // Error
                    if let errorMessage {
                        Text(errorMessage)
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
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.horizontal)
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    // Server URL toggle
                    Button {
                        withAnimation { showServerURL.toggle() }
                    } label: {
                        Text(showServerURL ? "Hide server settings" : "Configure server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }

    private func signIn() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await auth.login(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                baseURL: serverURL.trimmingCharacters(in: .whitespaces)
            )
        } catch let e as APIServiceError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
