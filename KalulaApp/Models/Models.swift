import Foundation

// MARK: - Auth

/// Flexible login response — backend returns either a full session OR an MFA challenge
struct FlexLoginResponse: Decodable {
    let accessToken: String?
    let user: KalulaUser?
    let mfaRequired: Bool?
    let tempToken: String?
}

struct LoginResponse: Codable {
    let accessToken: String
    let user: KalulaUser
}

struct MfaVerifyRequest: Encodable {
    let tempToken: String
    let code: String
}

// MARK: - Passkey (WebAuthn)

struct PasskeyAuthOptionsRequest: Encodable {
    let email: String
}

/// The server's PublicKeyCredentialRequestOptions (simplified — only fields we need)
struct PasskeyAuthOptions: Decodable {
    let challenge: String        // base64url
    let rpId: String?
    let timeout: Int?
    let userVerification: String?
    let allowCredentials: [AllowedCredential]?

    struct AllowedCredential: Decodable {
        let id: String
        let type: String
    }
}

/// What we send back to verify-auth — mirrors AuthenticationResponseJSON from simplewebauthn
struct PasskeyVerifyRequest: Encodable {
    let email: String
    let response: PasskeyAssertionResponse

    struct PasskeyAssertionResponse: Encodable {
        let id: String
        let rawId: String
        let type: String
        let response: AuthenticatorAssertionResponse
        let clientExtensionResults: [String: String]

        struct AuthenticatorAssertionResponse: Encodable {
            let clientDataJSON: String
            let authenticatorData: String
            let signature: String
            let userHandle: String?
        }
    }
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

    init(from decoder: Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        id          = try  c.decode(String.self,      forKey: .id)
        number      = try  c.decode(String.self,      forKey: .number)
        status      = (try? c.decode(String.self,     forKey: .status))      ?? "DRAFT"
        projectName = try? c.decode(String.self,      forKey: .projectName)
        notes       = try? c.decode(String.self,      forKey: .notes)
        subtotal    = (try? c.decode(Double.self,     forKey: .subtotal))    ?? 0
        tax         = (try? c.decode(Double.self,     forKey: .tax))         ?? 0
        total       = (try? c.decode(Double.self,     forKey: .total))       ?? 0
        validUntil  = try? c.decode(String.self,      forKey: .validUntil)
        createdAt   = (try? c.decode(String.self,     forKey: .createdAt))   ?? ""
        contact     = try? c.decode(QuoteContact.self, forKey: .contact)
        lineItems   = (try? c.decode([LineItem].self, forKey: .lineItems))   ?? []
    }

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

    init(from decoder: Decoder) throws {
        let c   = try decoder.container(keyedBy: CodingKeys.self)
        id          = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        quantity    = (try? c.decode(Double.self,  forKey: .quantity))    ?? 1
        unitPrice   = (try? c.decode(Double.self,  forKey: .unitPrice))   ?? 0
        total       = (try? c.decode(Double.self,  forKey: .total))       ?? 0
    }
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
    let companyName: String?
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
    let paidAt: String?
    let createdAt: String
    let contact: QuoteContact?
    var lineItems: [LineItem]

    init(from decoder: Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        id          = try  c.decode(String.self,       forKey: .id)
        number      = try  c.decode(String.self,       forKey: .number)
        status      = (try? c.decode(String.self,      forKey: .status))     ?? "DRAFT"
        projectName = try? c.decode(String.self,       forKey: .projectName)
        notes       = try? c.decode(String.self,       forKey: .notes)
        subtotal    = (try? c.decode(Double.self,      forKey: .subtotal))   ?? 0
        tax         = (try? c.decode(Double.self,      forKey: .tax))        ?? 0
        total       = (try? c.decode(Double.self,      forKey: .total))      ?? 0
        dueDate     = try? c.decode(String.self,       forKey: .dueDate)
        paidAt      = try? c.decode(String.self,       forKey: .paidAt)
        createdAt   = (try? c.decode(String.self,      forKey: .createdAt))  ?? ""
        contact     = try? c.decode(QuoteContact.self, forKey: .contact)
        lineItems   = (try? c.decode([LineItem].self,  forKey: .lineItems))  ?? []
    }
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
    let firstName:   String
    let lastName:    String
    let companyName: String?
    let email:       String?
    let phone:       String?
    let status:      String
}

struct CreateMobileQuoteRequest: Encodable {
    let contactId: String?
    let projectName: String?
    let validUntil: String?
    let notes: String?
    let taxRate: Double
    let lineItems: [CreateLineItem]
}

struct DocumentNumberFormat: Codable {
    var prefix:     String
    var separator:  String
    var dateFormat: String
    var seqDigits:  Int
}

struct CompanyDocumentSettings: Codable {
    let quoteNumberFormat:   DocumentNumberFormat?
    let invoiceNumberFormat: DocumentNumberFormat?
    let fiscalYearEndMonth:  Int?
}

struct CompanySettings: Codable {
    let name:         String?
    let contactEmail: String?
    let contactPhone: String?
    let address:      String?
    let logoBase64:   String?
    let taxRate:      Double?
    let currency:     String?
    let settings:     CompanyDocumentSettings?
}

struct UpdateCompanySettings: Encodable {
    let name:         String?
    let contactEmail: String?
    let contactPhone: String?
    let address:      String?
    let taxRate:      Double?
    let currency:     String?
    let settings:     CompanyDocumentSettings?
}

struct UpdateInvoiceRequest: Encodable {
    let status:      String?
    let projectName: String?
    let dueDate:     String?
    let notes:       String?
    let taxRate:     Double?
    let lineItems:   [CreateLineItem]?
}

struct UpdateQuoteRequest: Encodable {
    let status:      String?
    let projectName: String?
    let validUntil:  String?
    let notes:       String?
    let taxRate:     Double?
    let lineItems:   [CreateLineItem]?
}

struct UpdateContactRequest: Encodable {
    let firstName:   String
    let lastName:    String
    let companyName: String?
    let email:       String?
    let phone:       String?
    let status:      String
}

// MARK: - Suppliers (Vendors in backend)

struct Supplier: Codable, Identifiable, Hashable {
    let id:            String
    let name:          String
    let contactPerson: String?
    let email:         String?
    let phone:         String?
    let website:       String?
    let taxNumber:     String?
    let address:       String?
    let notes:         String?
    let createdAt:     String?

    var displayName: String { name }

    var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let result = words.map { String($0.prefix(1)) }.joined().uppercased()
        return result.isEmpty ? String(name.prefix(2)).uppercased() : result
    }

    init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        id            = try  c.decode(String.self, forKey: .id)
        name          = (try? c.decode(String.self, forKey: .name)) ?? ""
        contactPerson = try? c.decode(String.self, forKey: .contactPerson)
        email         = try? c.decode(String.self, forKey: .email)
        phone         = try? c.decode(String.self, forKey: .phone)
        website       = try? c.decode(String.self, forKey: .website)
        taxNumber     = try? c.decode(String.self, forKey: .taxNumber)
        address       = try? c.decode(String.self, forKey: .address)
        notes         = try? c.decode(String.self, forKey: .notes)
        createdAt     = try? c.decode(String.self, forKey: .createdAt)
    }
}

struct CreateSupplierRequest: Encodable {
    let name:          String
    let contactPerson: String?
    let email:         String?
    let phone:         String?
    let website:       String?
    let taxNumber:     String?
    let notes:         String?
}

struct UpdateSupplierRequest: Encodable {
    let name:          String
    let contactPerson: String?
    let email:         String?
    let phone:         String?
    let website:       String?
    let taxNumber:     String?
    let notes:         String?
}

struct CreateExpenseRequest: Encodable {
    let vendorId:    String?
    let description: String?
    let amount:      Double
    let tax:         Double?
    let date:        String?
    let notes:       String?
    let reference:   String?
}

// MARK: - API Error

/// Backend can return `message` as either a String or [String]
struct APIError: Decodable, Error {
    let message: String
    let statusCode: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = try? c.decode(Int.self, forKey: .statusCode)
        if let single = try? c.decode(String.self, forKey: .message) {
            message = single
        } else if let array = try? c.decode([String].self, forKey: .message) {
            message = array.joined(separator: ". ")
        } else {
            message = "Unknown error"
        }
    }

    enum CodingKeys: String, CodingKey {
        case message, statusCode
    }
}
