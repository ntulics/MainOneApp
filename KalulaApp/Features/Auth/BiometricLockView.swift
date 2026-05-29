import SwiftUI
import LocalAuthentication

struct BiometricLockView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAuthenticating = false

    private var isDark: Bool { colorScheme == .dark }

    private var canvas: Color {
        isDark ? Color(red: 0.051, green: 0.059, blue: 0.094)
               : Color(red: 0.949, green: 0.953, blue: 0.973)
    }
    private var surface: Color {
        isDark ? Color(red: 0.082, green: 0.094, blue: 0.129) : .white
    }
    private var border: Color {
        isDark ? Color(red: 0.165, green: 0.184, blue: 0.259)
               : Color(red: 0.878, green: 0.894, blue: 0.941)
    }
    private var textPrimary: Color {
        isDark ? .white : Color(red: 0.122, green: 0.141, blue: 0.204)
    }
    private var textSecondary: Color {
        isDark ? Color.white.opacity(0.50)
               : Color(red: 0.369, green: 0.392, blue: 0.478)
    }

    private var biometricIcon: String {
        auth.biometricType == .faceID ? "faceid" : "touchid"
    }

    private var biometricLabel: String {
        auth.biometricType == .faceID ? "Face ID" : "Touch ID"
    }

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                Image("logo-wordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .padding(.bottom, 48)

                // Lock card
                VStack(spacing: 24) {
                    // Biometric icon badge
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.075, green: 0.400, blue: 0.937).opacity(0.12))
                            .frame(width: 88, height: 88)
                        Circle()
                            .strokeBorder(Color(red: 0.075, green: 0.400, blue: 0.937).opacity(0.30),
                                          lineWidth: 1.5)
                            .frame(width: 88, height: 88)
                        Image(systemName: biometricIcon)
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Color(red: 0.075, green: 0.400, blue: 0.937))
                    }

                    VStack(spacing: 6) {
                        Text("Welcome back")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(textPrimary)
                        Text(auth.currentUser?.displayName
                             ?? auth.currentUser?.email
                             ?? "Sign in to continue")
                            .font(.system(size: 14))
                            .foregroundStyle(textSecondary)
                            .lineLimit(1)
                    }

                    // Error message
                    if let err = auth.biometricError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.972, green: 0.427, blue: 0.427))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Unlock button
                    Button {
                        Task { await unlock() }
                    } label: {
                        HStack(spacing: 10) {
                            if isAuthenticating {
                                ProgressView().tint(.white).scaleEffect(0.9)
                            } else {
                                Image(systemName: biometricIcon)
                                    .font(.system(size: 17, weight: .medium))
                                Text("Unlock with \(biometricLabel)")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.075, green: 0.400, blue: 0.937),
                                         Color(red: 0.059, green: 0.337, blue: 0.871)],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: Color(red: 0.075, green: 0.400, blue: 0.937).opacity(0.40),
                                radius: 12, x: 0, y: 6)
                    }
                    .disabled(isAuthenticating)

                    // Use password instead
                    Button {
                        auth.cancelBiometricLock()
                    } label: {
                        Text("Use password instead")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(red: 0.075, green: 0.400, blue: 0.937))
                    }
                }
                .padding(28)
                .background(surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5))
                .padding(.horizontal, 28)

                Spacer()
            }
        }
        .task { await unlock() }   // auto-prompt on appear
    }

    private func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        await auth.authenticateWithBiometrics()
        isAuthenticating = false
    }
}
