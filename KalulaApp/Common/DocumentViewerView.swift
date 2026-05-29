import SwiftUI
import PDFKit

// Inline viewer for documents fetched through the backend proxy.
// Pass a documentId and it downloads + renders PDF or image content.

struct DocumentViewerView: View {
    let documentId: String

    @State private var loadState: DocLoadState = .loading

    enum DocLoadState {
        case loading
        case pdf(PDFDocument)
        case image(UIImage)
        case failed(String)
    }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                VStack(spacing: 10) {
                    ProgressView().scaleEffect(1.2)
                    Text("Loading document…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))

            case .pdf(let doc):
                PDFKitView(document: doc)

            case .image(let img):
                GeometryReader { geo in
                    ScrollView {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: geo.size.width)
                            .padding(16)
                    }
                }
                .background(Color(.systemGroupedBackground))

            case .failed(let msg):
                VStack(spacing: 16) {
                    Image(systemName: "doc.slash")
                        .font(.system(size: 52))
                        .foregroundStyle(Color(.systemGray4))
                    Text("Could not load document")
                        .font(.subheadline.bold())
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Try again") { Task { await fetch() } }
                        .buttonStyle(.bordered)
                        .tint(.brand)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
        .task(id: documentId) { await fetch() }
    }

    private func fetch() async {
        loadState = .loading
        do {
            let (data, ext) = try await APIService.shared.download("/documents/\(documentId)/view")
            if ext == "pdf", let doc = PDFDocument(data: data) {
                loadState = .pdf(doc)
            } else if let img = UIImage(data: data) {
                loadState = .image(img)
            } else {
                loadState = .failed("Unsupported file format")
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - PDFKit wrapper

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor.systemGroupedBackground
        v.document = document
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}
