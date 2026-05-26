import Vision
import UIKit

enum OCRServiceError: LocalizedError {
    case recognitionFailed
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .recognitionFailed: return "Failed to run text recognition."
        case .noTextFound:       return "No text could be extracted from the scan."
        }
    }
}

final class OCRService {
    static let shared = OCRService()

    func recognizeText(from images: [UIImage]) async throws -> String {
        var allText: [String] = []

        for image in images {
            guard let cgImage = image.cgImage else { continue }
            let pageText = try await recognizePage(cgImage: cgImage)
            if !pageText.isEmpty {
                allText.append(pageText)
            }
        }

        let combined = allText.joined(separator: "\n\n--- PAGE BREAK ---\n\n")
        if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OCRServiceError.noTextFound
        }
        return combined
    }

    private func recognizePage(cgImage: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap {
                    $0.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
