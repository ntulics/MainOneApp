import Foundation

// MARK: - Auth

struct LoginResponse: Codable {
    let accessToken: String
    let user: KalulaUser
}

struct KalulaUser: Codable, Identifiable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let role: String
    let tenantId: String

    var displayName: String {
        let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? email : parts.joined(separator: " ")
    }

    var initials: String {
        let parts = [firstName, lastName].compactMap { $0?.first.map(String.init) }
        return parts.isEmpty ? String(email.prefix(2)).uppercased() : parts.joined()
    }
}

// MARK: - Quotes

struct Quote: Codable, Identifiable, Hashable {
    let id: String
    let number: String
    let status: String
    let projectName: String?
    let notes: String?
    let subtotal: Double
    let tax: Double
    let total: Double
    let validUntil: String?
    let createdAt: String
    let contact: QuoteContact?
    var lineItems: [LineItem]

    var statusColor: String {
        switch status {
        case "DRAFT":    return "gray"
        case "SENT":     return "blue"
        case "ACCEPTED": return "green"
        case "DECLINED": return "red"
        case "EXPIRED":  return "orange"
        default:         return "gray"
        }
    }
}

struct QuoteContact: Codable, Hashable {
    let id: String
    let firstName: String?
    let lastName: String?
    let email: String?

    var displayName: String {
        let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? (email ?? "Unknown") : parts.joined(separator: " ")
    }
}

struct LineItem: Codable, Identifiable, Hashable {
    let id: String
    var description: String
    var quantity: Double
    var unitPrice: Double
    var total: Double
}

// MARK: - Documents

enum DocumentType: String, Codable, CaseIterable {
    case vendorQuote = "VENDOR_QUOTE"
    case receipt     = "RECEIPT"
    case general     = "GENERAL"
    case invoice     = "INVOICE"
    case important   = "IMPORTANT"

    var displayName: String {
        switch self {
        case .vendorQuote: return "Vendor Quote"
        case .receipt:     return "Receipt"
        case .general:     return "General"
        case .invoice:     return "Invoice"
        case .important:   return "Important"
        }
    }

    var iconName: String {
        switch self {
        case .vendorQuote: return "doc.text.magnifyingglass"
        case .receipt:     return "receipt"
        case .general:     return "doc"
        case .invoice:     return "doc.plaintext"
        case .important:   return "star.circle"
        }
    }
}

struct ScannedDocument: Codable, Identifiable {
    let id: String
    let type: DocumentType
    let fileName: String
    let blobUrl: String
    let fileSize: Int?
    let notes: String?
    let metadata: DocumentMetadata?
    let sourceQuoteId: String?
    let createdAt: String

    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return createdAt
    }

    var fileSizeFormatted: String {
        guard let size = fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct DocumentMetadata: Codable {
    let vendor: String?
    let amount: Double?
    let currency: String?
    let date: String?
    let referenceNumber: String?
}

// MARK: - Upload

struct UploadUrlResponse: Codable {
    let uploadUrl: String
    let blobPath: String
    let blobUrl: String
    let documentId: String
}

// MARK: - Quote Parsing

struct ParseQuoteRequest: Codable {
    let ocrText: String
    let pageCount: Int
}

struct ParsedQuote: Codable {
    let projectName: String?
    let notes: String?
    let vendorName: String?
    let lineItems: [ParsedLineItem]
    let subtotal: Double?
    let tax: Double?
    let total: Double?
    let currency: String?
}

struct ParsedLineItem: Codable, Identifiable {
    var id: String = UUID().uuidString
    var description: String
    var quantity: Double
    var unitPrice: Double
    var total: Double

    enum CodingKeys: String, CodingKey {
        case description, quantity, unitPrice, total
    }
}

// MARK: - Create Quote

struct CreateQuoteRequest: Codable {
    let projectName: String?
    let notes: String?
    let tax: Double
    let lineItems: [CreateLineItem]
    let sourceDocumentId: String?
}

struct CreateLineItem: Codable {
    let description: String
    let quantity: Double
    let unitPrice: Double
    let total: Double
}

// MARK: - CRM Contacts

struct CRMContact: Codable, Identifiable, Hashable {
    let id: String
    let firstName: String
    let lastName: String
    let email: String?
    let phone: String?
    let status: String?
    let createdAt: String?

    var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? (email ?? "Unknown") : full
    }

    var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        let result = (f + l).uppercased()
        return result.isEmpty ? String((email ?? "?").prefix(2)).uppercased() : result
    }
}

struct ContactsResponse: Codable {
    let contacts: [CRMContact]
}

// MARK: - Invoices

struct Invoice: Codable, Identifiable, Hashable {
    let id: String
    let number: String
    let status: String
    let projectName: String?
    let notes: String?
    let subtotal: Double
    let tax: Double
    let total: Double
    let dueDate: String?
    let createdAt: String
    let contact: QuoteContact?
    var lineItems: [LineItem]
}

struct CreateInvoiceRequest: Encodable {
    let contactId: String?
    let projectName: String?
    let dueDate: String?
    let notes: String?
    let taxRate: Double
    let lineItems: [CreateLineItem]
}

struct CreateContactRequest: Encodable {
    let firstName: String
    let lastName: String
    let email: String?
    let phone: String?
    let status: String
}

struct CreateMobileQuoteRequest: Encodable {
    let contactId: String?
    let projectName: String?
    let validUntil: String?
    let notes: String?
    let taxRate: Double
    let lineItems: [CreateLineItem]
}

// MARK: - API Error

struct APIError: Codable, Error {
    let message: String
    let statusCode: Int?
}
