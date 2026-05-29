import SwiftUI

// Full-screen scanner flow: camera → type selection → processing → result
struct ScannerView: View {
    let initialType: DocumentType
    var onScanned: ((ParsedQuote) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var phase: ScanPhase = .camera
    @State private var scannedImages: [UIImage] = []
    @State private var selectedType: DocumentType
    @State private var notes = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var parsedQuote: ParsedQuote?
    @State private var savedDocument: ScannedDocument?

    init(initialType: DocumentType, onScanned: ((ParsedQuote) -> Void)? = nil) {
        self.initialType = initialType
        self.onScanned = onScanned
        _selectedType = State(initialValue: initialType)
    }

    enum ScanPhase {
        case camera, typeSelection, processing, quoteReview, success
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch phase {
                case .camera:
                    DocumentCameraView(
                        onScan: { images in
                            scannedImages = images
                            phase = .typeSelection
                        },
                        onCancel: { dismiss() }
                    )
                    .ignoresSafeArea()

                case .typeSelection:
                    TypeSelectionView(
                        images: scannedImages,
                        selectedType: $selectedType,
                        notes: $notes,
                        onContinue: { Task { await processDocument() } },
                        onRescan: { phase = .camera }
                    )

                case .processing:
                    ProcessingView(type: selectedType)

                case .quoteReview:
                    if let parsed = parsedQuote {
                        QuoteReviewView(
                            parsed: parsed,
                            onCreateQuote: { lineItems in
                                Task { await createQuote(from: lineItems) }
                            },
                            onSkip: { dismiss() }
                        )
                    }

                case .success:
                    SuccessView(
                        document: savedDocument,
                        type: selectedType,
                        onDone: { dismiss() }
                    )
                }
            }
            .navigationBarHidden(phase == .camera)
            .toolbar {
                if phase != .camera {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { errorMessage = nil; phase = .typeSelection }
            } message: {
                Text(errorMessage ?? "An unexpected error occurred.")
            }
        }
    }

    private func processDocument() async {
        phase = .processing
        isProcessing = true

        do {
            if selectedType == .vendorQuote {
                // OCR + parse
                let parsed = try await DocumentService.shared.parseVendorQuote(images: scannedImages)
                parsedQuote = parsed
                if let onScanned {
                    // Inline mode: return parsed data to caller and dismiss
                    onScanned(parsed)
                    dismiss()
                } else {
                    phase = .quoteReview
                }
            } else {
                // Upload directly
                let doc = try await DocumentService.shared.uploadScan(
                    images: scannedImages,
                    type: selectedType,
                    notes: notes.isEmpty ? nil : notes
                )
                savedDocument = doc
                phase = .success
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isProcessing = false
    }

    private func createQuote(from items: [ParsedLineItem]) async {
        phase = .processing
        do {
            // First upload the original scan
            let doc = try await DocumentService.shared.uploadScan(
                images: scannedImages,
                type: .vendorQuote,
                notes: "Vendor quote scan"
            )

            // Create the Kalula quote
            let req = CreateQuoteRequest(
                projectName: parsedQuote?.projectName,
                notes: parsedQuote?.notes,
                tax: parsedQuote?.tax ?? 0,
                lineItems: items.map {
                    CreateLineItem(description: $0.description, quantity: $0.quantity, unitPrice: $0.unitPrice, total: $0.total)
                },
                sourceDocumentId: doc.id
            )
            let _: Quote = try await APIService.shared.post("/quotes", body: req)
            savedDocument = doc
            phase = .success
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Sub-views

struct TypeSelectionView: View {
    let images: [UIImage]
    @Binding var selectedType: DocumentType
    @Binding var notes: String
    let onContinue: () -> Void
    let onRescan: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Preview of scanned pages
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(images.indices, id: \.self) { i in
                            Image(uiImage: images[i])
                                .resizable()
                                .scaledToFit()
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 4)
                        }
                    }
                    .padding(.horizontal)
                }

                Text("\(images.count) page\(images.count == 1 ? "" : "s") scanned")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Document type picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("What did you scan?")
                        .font(.headline)

                    ForEach(DocumentType.allCases, id: \.self) { type in
                        TypeOptionRow(type: type, isSelected: selectedType == type) {
                            selectedType = type
                        }
                    }
                }
                .padding(.horizontal)

                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes (optional)")
                        .font(.subheadline)
                    TextField("Add a note...", text: $notes, axis: .vertical)
                        .lineLimit(3)
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)

                // Actions
                VStack(spacing: 12) {
                    Button(action: onContinue) {
                        Label(continueLabel, systemImage: selectedType.iconName)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)

                    Button("Rescan", action: onRescan)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Review Scan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var continueLabel: String {
        switch selectedType {
        case .vendorQuote: return "Parse & Create Quote"
        case .receipt:     return "Upload Receipt"
        case .invoice:     return "Upload Invoice"
        case .important:   return "Upload Document"
        case .general:     return "Upload Document"
        }
    }
}

struct TypeOptionRow: View {
    let type: DocumentType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: type.iconName)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .brand)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected ? Color.brand : Color.brand.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(typeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.brand)
                }
            }
            .padding(14)
            .background(
                isSelected ? Color.brand.opacity(0.08) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.brand : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var typeDescription: String {
        switch type {
        case .vendorQuote: return "OCR → auto-generate your Kalula quote"
        case .receipt:     return "Store for accounting & tax records"
        case .invoice:     return "Archive a supplier invoice"
        case .important:   return "Company registration & critical docs"
        case .general:     return "Archive any document in your tenant folder"
        }
    }
}

struct ProcessingView: View {
    let type: DocumentType

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            Text(processingMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Processing")
    }

    private var processingMessage: String {
        switch type {
        case .vendorQuote: return "Reading text and extracting line items…"
        case .receipt:     return "Uploading receipt to secure storage…"
        case .invoice:     return "Uploading invoice to secure storage…"
        case .important:   return "Uploading document to secure storage…"
        case .general:     return "Uploading document to secure storage…"
        }
    }
}

struct SuccessView: View {
    let document: ScannedDocument?
    let type: DocumentType
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Saved Successfully")
                    .font(.title2.bold())
                Text(successMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(.brand)
        }
        .padding()
        .navigationTitle("Success")
    }

    private var successMessage: String {
        switch type {
        case .vendorQuote: return "Quote created and original scan archived."
        case .receipt:     return "Receipt stored in your tenant folder."
        case .invoice:     return "Invoice stored in your tenant folder."
        case .important:   return "Document stored in your tenant folder."
        case .general:     return "Document stored in your tenant folder."
        }
    }
}
