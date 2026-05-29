import SwiftUI
import PencilKit

// MARK: - PKCanvasView wrapper

struct SignatureCanvas: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool            = PKInkingTool(.pen, color: .label, width: 3)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque        = false
        canvasView.drawingPolicy   = .anyInput
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

// MARK: - Signature pad (standalone capture)

struct SignaturePadView: View {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var canvasView = PKCanvasView()
    @State private var isEmpty    = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Sign Here")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    canvasView.drawing = PKDrawing()
                    isEmpty = true
                }
                .foregroundStyle(.orange)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Instructions
            Text("Draw your signature below")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            // Canvas
            ZStack {
                Color(.secondarySystemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                SignatureCanvas(canvasView: $canvasView)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onChange(of: canvasView.drawing) { drawing in
                        isEmpty = drawing.strokes.isEmpty
                    }

                if isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "pencil.and.scribble")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("Sign above")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 200)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Bottom line indicator
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
                .padding(.horizontal, 40)
                .padding(.top, 8)

            Spacer(minLength: 24)

            // Apply button
            Button {
                let image = renderSignature()
                onCapture(image)
            } label: {
                Text("Apply Signature")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isEmpty ? Color.gray : Color.orange, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }

    private func renderSignature() -> UIImage {
        let bounds = canvasView.drawing.bounds.insetBy(dx: -10, dy: -10)
        guard !bounds.isEmpty else { return UIImage() }
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { ctx in
            UIColor.label.setFill()
            ctx.cgContext.fill(bounds)
            canvasView.drawing.image(from: bounds, scale: UIScreen.main.scale)
                .draw(in: bounds)
        }
    }
}

// MARK: - Document signing view

struct DocumentSigningView: View {
    let document: ScannedDocument

    @Environment(\.dismiss) private var dismiss
    @State private var showSignaturePad = false
    @State private var signature: UIImage?
    @State private var signaturePosition = CGPoint(x: 150, y: 400)
    @State private var signatureScale: CGFloat = 1.0
    @State private var documentURL: URL?
    @State private var isLoadingDoc   = false
    @State private var isSaving       = false
    @State private var savedOK        = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Document preview area
                        ZStack(alignment: .topLeading) {
                            documentPreview

                            // Draggable signature overlay
                            if let sig = signature {
                                Image(uiImage: sig)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180 * signatureScale, height: 70 * signatureScale)
                                    .position(signaturePosition)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { v in signaturePosition = v.location }
                                    )
                                    .gesture(
                                        MagnificationGesture()
                                            .onChanged { v in signatureScale = v }
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.orange.opacity(0.7), lineWidth: 1)
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 480)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        .padding(.horizontal, 16)

                        // Action buttons
                        VStack(spacing: 12) {
                            Button {
                                showSignaturePad = true
                            } label: {
                                Label(
                                    signature == nil ? "Add Signature" : "Change Signature",
                                    systemImage: "signature"
                                )
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
                            }

                            if signature != nil {
                                Text("Drag the signature to position it, pinch to resize")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)

                                Button {
                                    Task { await saveSignedDocument() }
                                } label: {
                                    if isSaving {
                                        ProgressView().tint(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(Color.green, in: RoundedRectangle(cornerRadius: 14))
                                    } else {
                                        Label("Save Signed Document", systemImage: "checkmark.circle.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(savedOK ? Color.gray : Color.green, in: RoundedRectangle(cornerRadius: 14))
                                    }
                                }
                                .disabled(isSaving || savedOK)
                            }

                            if let err = errorMessage {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                            if savedOK {
                                Label("Saved!", systemImage: "checkmark.circle.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Sign Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSignaturePad) {
                SignaturePadView(
                    onCapture: { img in
                        signature = img
                        showSignaturePad = false
                    },
                    onCancel: { showSignaturePad = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task { await loadDocumentURL() }
        }
    }

    // MARK: Document preview

    @ViewBuilder
    private var documentPreview: some View {
        if isLoadingDoc {
            ProgressView("Loading document…")
                .frame(maxWidth: .infinity, minHeight: 480)
                .background(Color(.secondarySystemGroupedBackground))
        } else if let url = documentURL {
            QuickLookPreview(url: url)
                .frame(maxWidth: .infinity, minHeight: 480)
        } else {
            VStack(spacing: 12) {
                Image(systemName: document.type.iconName)
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text(document.fileName)
                    .font(.headline)
                Text("Preview unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 480)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Helpers

    private func loadDocumentURL() async {
        isLoadingDoc = true
        documentURL  = try? await DocumentService.shared.viewDocument(document)
        isLoadingDoc = false
    }

    private func saveSignedDocument() async {
        guard let sig = signature, let docURL = documentURL else { return }
        isSaving = true; errorMessage = nil

        do {
            // Composite: render the document page with the signature overlay as JPEG
            let docData  = (try? Data(contentsOf: docURL)) ?? Data()
            guard let docImage = UIImage(data: docData) else { throw NSError(domain: "sign", code: 0) }

            let size = docImage.size
            UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
            docImage.draw(in: CGRect(origin: .zero, size: size))

            // Scale signature position from screen coords to image coords
            let scaleX = size.width  / UIScreen.main.bounds.width
            let scaleY = size.height / 480
            let sigW   = 180 * signatureScale * scaleX
            let sigH   = 70  * signatureScale * scaleY
            let sigRect = CGRect(
                x: signaturePosition.x * scaleX - sigW / 2,
                y: signaturePosition.y * scaleY - sigH / 2,
                width: sigW, height: sigH
            )
            sig.draw(in: sigRect)
            let result = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            guard let jpeg = result?.jpegData(compressionQuality: 0.88) else { throw NSError(domain: "sign", code: 1) }

            let name = "signed_\(document.fileName.components(separatedBy: ".").first ?? "doc").jpg"
            _ = try await DocumentService.shared.uploadFile(
                data:     jpeg,
                fileName: name,
                mimeType: "image/jpeg",
                type:     document.type,
                notes:    "Signed version of \(document.fileName)"
            )
            savedOK = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
