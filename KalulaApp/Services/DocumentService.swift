import UIKit

final class DocumentService {
    static let shared = DocumentService()

    // MARK: - Upload (3-step: get SAS → PUT to Azure → confirm)

    func uploadScan(
        images: [UIImage],
        type: DocumentType,
        notes: String? = nil
    ) async throws -> ScannedDocument {
        guard !images.isEmpty else { throw APIServiceError.noData }

        let imageData = images.count == 1
            ? (images[0].jpegData(compressionQuality: 0.85) ?? Data())
            : renderMultipage(images: images)

        let fileName = "\(UUID().uuidString).jpg"

        // Step 1 — ask backend for a short-lived SAS upload URL
        struct UploadRequest: Encodable {
            let fileName, type, mimeType: String
            let fileSize: Int
        }
        let urlResponse: UploadUrlResponse = try await APIService.shared.post(
            "/documents/upload-url",
            body: UploadRequest(
                fileName: fileName,
                type:     type.rawValue,
                mimeType: "image/jpeg",
                fileSize: imageData.count
            )
        )

        // Step 2 — PUT the image directly to Azure using the SAS URL
        try await APIService.shared.uploadToAzure(
            sasUrl:      urlResponse.uploadUrl,
            data:        imageData,
            contentType: "image/jpeg"
        )

        // Step 3 — tell the backend the upload is done
        struct ConfirmRequest: Encodable {
            let documentId: String
            let notes: String?
        }
        let saved: ScannedDocument = try await APIService.shared.post(
            "/documents/confirm",
            body: ConfirmRequest(documentId: urlResponse.documentId, notes: notes)
        )
        return saved
    }

    // MARK: - Parse vendor quote (OCR on-device → AI parse on backend)

    func parseVendorQuote(images: [UIImage]) async throws -> ParsedQuote {
        let ocrText = try await OCRService.shared.recognizeText(from: images)
        let req = ParseQuoteRequest(ocrText: ocrText, pageCount: images.count)
        return try await APIService.shared.post("/documents/parse-quote", body: req)
    }

    // MARK: - List & delete

    func getDocuments(type: DocumentType? = nil) async throws -> [ScannedDocument] {
        var path = "/documents"
        if let type { path += "?type=\(type.rawValue)" }
        return try await APIService.shared.get(path)
    }

    func deleteDocument(id: String) async throws {
        try await APIService.shared.delete("/documents/\(id)")
    }

    /// Downloads a document through the backend proxy and saves to a temp file
    /// for display with QuickLook — no Azure URL is ever exposed.
    func viewDocument(_ doc: ScannedDocument) async throws -> URL {
        let (data, ext) = try await APIService.shared.download("/documents/\(doc.id)/view")
        let tmpDir  = FileManager.default.temporaryDirectory
        let tmpURL  = tmpDir.appendingPathComponent("\(doc.id).\(ext)")
        try data.write(to: tmpURL)
        return tmpURL
    }

    // MARK: - Helpers

    private func renderMultipage(images: [UIImage]) -> Data {
        guard let first = images.first else { return Data() }
        let size = CGSize(width: first.size.width, height: first.size.height * CGFloat(images.count))
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        for (i, img) in images.enumerated() {
            img.draw(in: CGRect(
                x: 0, y: first.size.height * CGFloat(i),
                width: first.size.width, height: first.size.height
            ))
        }
        let combined = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return combined?.jpegData(compressionQuality: 0.85) ?? Data()
    }
}
