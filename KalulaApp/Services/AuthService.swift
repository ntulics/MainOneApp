import Foundation
import AuthenticationServices
import LocalAuthentication

// MARK: - AuthService

@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    /// The production API URL — never configurable by the user.
    static let baseURL = "https://mainone.co.za/v1"

    private let tokenKey        = "kalula_jwt"
    private let biometricEnabledKey = "kalula_biometric_enabled"

    @Published var currentUser: KalulaUser?
    @Published var isAuthenticated = false

    // Biometric lock — true when a stored session exists but hasn't been unlocked yet
    @Published var isBiometricLocked = false
    @Published var biometricError: String?

    // MFA challenge state
    @Published var mfaPending = false
    @Published var mfaTempToken: String?

    // Passkey state
    @Published var passkeyPending = false
    private var passkeyCompletion: CheckedContinuation<LoginResponse, Error>?
    private var passkeyEmail: String = ""

    // MARK: - Biometric availability

    var biometricType: LABiometryType {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            return .none
        }
        return ctx.biometryType
    }

    var biometricEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: biometricEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: biometricEnabledKey) }
    }

    // MARK: - Session restore

    /// Called on app launch. Never auto-restores if biometrics are enabled —
    /// the user must tap the Face ID / Touch ID button on the login screen.
    func restoreSession() async {
        guard let token = KeychainHelper.read(tokenKey) else { return }

        // Biometrics enabled — surface the button on the login page instead
        if biometricEnabled && biometricType != .none { return }

        await unlockSession(token: token)
    }

    /// True when a stored token exists and biometrics are enabled —
    /// used by LoginView to decide whether to show the biometric button.
    var hasSavedSession: Bool {
        KeychainHelper.read(tokenKey) != nil && biometricEnabled && biometricType != .none
    }

    /// Triggered by the Face ID / Touch ID button on the login screen.
    func authenticateWithBiometrics() async {
        let ctx = LAContext()
        let reason = "Sign in to MainOne"
        biometricError = nil

        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            guard ok else { return }
        } catch {
            let laError = error as? LAError
            if laError?.code != .userCancel && laError?.code != .systemCancel {
                biometricError = error.localizedDescription
            }
            return
        }

        guard let token = KeychainHelper.read(tokenKey) else { return }
        await unlockSession(token: token)
    }

    private func unlockSession(token: String) async {
        await APIService.shared.setToken(token)
        do {
            let user: KalulaUser = try await APIService.shared.get("/auth/me")
            currentUser       = user
            isAuthenticated   = true
            isBiometricLocked = false
            biometricError    = nil
        } catch {
            logout()
        }
    }

    // MARK: - Email + Password login

    func login(email: String, password: String) async throws {
        struct LoginBody: Encodable { let email, password: String }
        let raw: FlexLoginResponse = try await APIService.shared.post(
            "/auth/login",
            body: LoginBody(email: email, password: password)
        )

        if raw.mfaRequired == true, let tempToken = raw.tempToken {
            // MFA is required — surface the TOTP step
            mfaTempToken = tempToken
            mfaPending   = true
            return
        }

        guard let token = raw.accessToken, let user = raw.user else {
            throw APIServiceError.httpError(500, "Unexpected response from server")
        }

        await finaliseSession(token: token, user: user)
    }

    // MARK: - MFA (TOTP) step

    func verifyMfa(code: String) async throws {
        guard let tempToken = mfaTempToken else {
            throw APIServiceError.httpError(400, "No MFA challenge in progress")
        }

        let response: LoginResponse = try await APIService.shared.post(
            "/auth/mfa/verify-login",
            body: MfaVerifyRequest(tempToken: tempToken, code: code)
        )

        mfaPending   = false
        mfaTempToken = nil
        await finaliseSession(token: response.accessToken, user: response.user)
    }

    func cancelMfa() {
        mfaPending   = false
        mfaTempToken = nil
    }

    // MARK: - Passkey login

    /// Starts the passkey authentication flow.
    /// - Fetches a WebAuthn challenge from the server for the given email.
    /// - Presents the system passkey UI.
    /// - On success, verifies the assertion with the server and logs in.
    func loginWithPasskey(email: String) async throws {
        passkeyEmail = email

        // 1. Fetch challenge from server
        let options: PasskeyAuthOptions = try await APIService.shared.post(
            "/auth/passkey/auth-options",
            body: PasskeyAuthOptionsRequest(email: email)
        )

        // 2. Decode the base64url challenge to Data
        guard let challengeData = Data(base64urlEncoded: options.challenge) else {
            throw APIServiceError.httpError(400, "Invalid passkey challenge from server")
        }

        // 3. Build the platform credential request
        let rpId = options.rpId ?? "mainone.co.za"
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let assertionRequest = provider.createCredentialAssertionRequest(challenge: challengeData)

        if let allowCreds = options.allowCredentials, !allowCreds.isEmpty {
            assertionRequest.allowedCredentials = allowCreds.compactMap {
                guard let id = Data(base64urlEncoded: $0.id) else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: id)
            }
        }

        // 4. Present system UI and await result via continuation
        let response: LoginResponse = try await withCheckedThrowingContinuation { cont in
            self.passkeyCompletion = cont
            let controller = ASAuthorizationController(authorizationRequests: [assertionRequest])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        await finaliseSession(token: response.accessToken, user: response.user)
    }

    // MARK: - Session finalisation

    private func finaliseSession(token: String, user: KalulaUser) async {
        KeychainHelper.save(token, key: tokenKey)
        await APIService.shared.setToken(token)
        currentUser       = user
        isAuthenticated   = true
        isBiometricLocked = false
        // Auto-enable biometrics after first successful login if device supports it
        if biometricType != .none {
            biometricEnabled = true
        }
    }

    // MARK: - Logout

    func logout() {
        KeychainHelper.delete(tokenKey)
        Task { await APIService.shared.setToken(nil) }
        currentUser     = nil
        isAuthenticated = false
        mfaPending      = false
        mfaTempToken    = nil
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            Task { @MainActor in
                self.passkeyCompletion?.resume(throwing: APIServiceError.httpError(400, "Unexpected credential type"))
                self.passkeyCompletion = nil
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await self.sendPasskeyAssertion(credential: credential)
                self.passkeyCompletion?.resume(returning: response)
            } catch {
                self.passkeyCompletion?.resume(throwing: error)
            }
            self.passkeyCompletion = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                self.passkeyCompletion?.resume(throwing: APIServiceError.httpError(0, "Passkey authentication cancelled"))
            } else {
                self.passkeyCompletion?.resume(throwing: APIServiceError.httpError(0, error.localizedDescription))
            }
            self.passkeyCompletion = nil
        }
    }

    // Sends the platform assertion to the backend for verification
    private func sendPasskeyAssertion(credential: ASAuthorizationPlatformPublicKeyCredentialAssertion) async throws -> LoginResponse {
        let credIdB64   = credential.credentialID.base64urlEncodedString()
        let clientJSON  = credential.rawClientDataJSON.base64urlEncodedString()
        let authData    = credential.rawAuthenticatorData.base64urlEncodedString()
        let signature   = credential.signature.base64urlEncodedString()
        let userHandle  = credential.userID.isEmpty ? nil : credential.userID.base64urlEncodedString()

        let body = PasskeyVerifyRequest(
            email: passkeyEmail,
            response: PasskeyVerifyRequest.PasskeyAssertionResponse(
                id: credIdB64,
                rawId: credIdB64,
                type: "public-key",
                response: PasskeyVerifyRequest.PasskeyAssertionResponse.AuthenticatorAssertionResponse(
                    clientDataJSON: clientJSON,
                    authenticatorData: authData,
                    signature: signature,
                    userHandle: userHandle
                ),
                clientExtensionResults: [:]
            )
        )

        return try await APIService.shared.post("/auth/passkey/verify-auth", body: body)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // ASAuthorizationController always calls this on the main thread, so it's safe to
        // assume main-actor isolation here. MainActor.assumeIsolated avoids the warning.
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            return windowScene?.windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
        }
    }
}

// MARK: - Keychain helper

enum KeychainHelper {
    static func save(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Base64URL helpers

private extension Data {
    init?(base64urlEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        self.init(base64Encoded: base64)
    }

    func base64urlEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
