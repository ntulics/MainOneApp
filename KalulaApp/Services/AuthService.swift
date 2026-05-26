import Foundation

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    private let tokenKey = "kalula_jwt"
    private let baseURLKey = "kalula_base_url"

    @Published var currentUser: KalulaUser?
    @Published var isAuthenticated = false

    var savedBaseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "https://platform.underpin.co.za/v1" }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    func restoreSession() async {
        guard let token = KeychainHelper.read(tokenKey) else { return }
        await APIService.shared.setToken(token)
        await APIService.shared.setBaseURL(savedBaseURL)

        do {
            let user: KalulaUser = try await APIService.shared.get("/auth/me")
            currentUser = user
            isAuthenticated = true
        } catch {
            logout()
        }
    }

    func login(email: String, password: String, baseURL: String) async throws {
        savedBaseURL = baseURL
        await APIService.shared.setBaseURL(baseURL)

        struct LoginBody: Encodable { let email, password: String }
        let response: LoginResponse = try await APIService.shared.post(
            "/auth/login",
            body: LoginBody(email: email, password: password)
        )

        KeychainHelper.save(response.accessToken, key: tokenKey)
        await APIService.shared.setToken(response.accessToken)
        currentUser = response.user
        isAuthenticated = true
    }

    func logout() {
        KeychainHelper.delete(tokenKey)
        Task { await APIService.shared.setToken(nil) }
        currentUser = nil
        isAuthenticated = false
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
