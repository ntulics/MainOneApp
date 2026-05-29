import Foundation

enum APIServiceError: LocalizedError {
    case invalidURL
    case noData
    case httpError(Int, String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid URL"
        case .noData:               return "No data received"
        case .httpError(_, let m):  return m
        case .decodingError(let m): return "Parsing error: \(m)"
        }
    }
}

actor APIService {
    static let shared = APIService()

    /// Production API base URL — always points to mainone.co.za
    private let baseURL: String = AuthService.baseURL
    private var authToken: String?

    func setToken(_ token: String?) { authToken = token }

    // MARK: - Generic JSON request

    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIServiceError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Send the app's origin so the backend allows passkey assertions
        req.setValue("https://mainone.co.za", forHTTPHeaderField: "Origin")
        if let token = authToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body  { req.httpBody = try JSONEncoder().encode(body) }

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIServiceError.httpError(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIServiceError.decodingError(error.localizedDescription)
        }
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request("GET", path: path)
    }

    func post<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("POST", path: path, body: body)
    }

    func put<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("PUT", path: path, body: body)
    }

    func patch<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request("PATCH", path: path, body: body)
    }

    @discardableResult
    func delete(_ path: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIServiceError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        if let token = authToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    // MARK: - Authenticated document download (no Azure URL exposed)

    func download(_ path: String) async throws -> (Data, String) {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIServiceError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = authToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIServiceError.httpError(http.statusCode, "Download failed (\(http.statusCode))")
        }
        let ct = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let ext: String
        if ct.contains("pdf")  { ext = "pdf" }
        else if ct.contains("jpeg") || ct.contains("jpg") { ext = "jpg" }
        else if ct.contains("png")  { ext = "png" }
        else { ext = "bin" }
        return (data, ext)
    }

    // MARK: - Direct Azure Blob Storage upload (SAS URL)

    func uploadToAzure(sasUrl: String, data: Data, contentType: String) async throws {
        guard let url = URL(string: sasUrl) else { throw APIServiceError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        req.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIServiceError.httpError(http.statusCode, "Azure upload failed (\(http.statusCode))")
        }
    }
}
