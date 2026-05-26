import SwiftUI
import QuickLook

// MARK: - View model

@MainActor
final class DocumentsViewModel: ObservableObject {
    @Published var documents: [ScannedDocument] = []
    @Published var selectedType: DocumentType? = nil   // nil = all types
    @Published var isLoading   = false
    @Published var errorMessage: String?

    func load() async {
        isLoading   = true
        errorMessage = nil
        do {
            // Pass selectedType filter; nil means all documents
            documents = try await DocumentService.shared.getDocuments(type: selectedType)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ doc: ScannedDocument) async {
        try? await DocumentService.shared.deleteDocument(id: doc.id)
        documents.removeAll { $0.id == doc.id }
    }
}

// MARK: - Main view

struct DocumentsView: View {
    @StateObject private var vm = DocumentsViewModel()
    @State private var viewingDoc: ScannedDocument?
    @State private var quickLookURL: URL?
    @State private var showQuickLook = false
    @State private var isLoadingDoc  = false
    @State private var viewError: String?
    @State private var showViewError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Type filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: vm.selectedType == nil, tint: .orange) {
                            vm.selectedType = nil
                            Task { await vm.load() }
                        }
                        ForEach(DocumentType.allCases, id: \.self) { type in
                            FilterChip(label: type.displayName, isSelected: vm.selectedType == type, tint: .orange) {
                                vm.selectedType = type
                                Task { await vm.load() }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))

                Divider()

                Group {
                    if vm.isLoading && vm.documents.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = vm.errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") { Task { await vm.load() } }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if vm.documents.isEmpty {
                        EmptyStateView(
                            icon:    "folder",
                            title:   "No Documents",
                            message: vm.selectedType == nil
                                ? "Scan documents with the iOS app or upload PDFs on the web."
                                : "No \(vm.selectedType!.displayName.lowercased()) documents yet."
                        )
                    } else {
                        List {
                            ForEach(vm.documents) { doc in
                                DocumentRow(document: doc, isLoadingView: isLoadingDoc && viewingDoc?.id == doc.id) {
                                    Task { await openDocument(doc) }
                                }
                            }
                            .onDelete { indices in
                                let items = indices.map { vm.documents[$0] }
                                Task { for d in items { await vm.delete(d) } }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await vm.load() }
                    }
                }
            }
            .navigationTitle("Documents")
            .task { await vm.load() }
            .alert("Error", isPresented: $showViewError) {
                Button("OK") {}
            } message: {
                Text(viewError ?? "Could not open document.")
            }
            .sheet(isPresented: $showQuickLook, onDismiss: cleanupTempFile) {
                if let url = quickLookURL {
                    QuickLookPreview(url: url)
                        .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: - Document viewer

    private func openDocument(_ doc: ScannedDocument) async {
        viewingDoc   = doc
        isLoadingDoc = true
        do {
            let url = try await DocumentService.shared.viewDocument(doc)
            quickLookURL = url
            showQuickLook = true
        } catch {
            viewError     = error.localizedDescription
            showViewError = true
        }
        isLoadingDoc = false
        viewingDoc   = nil
    }

    private func cleanupTempFile() {
        if let url = quickLookURL {
            try? FileManager.default.removeItem(at: url)
            quickLookURL = nil
        }
    }
}

// MARK: - Sub-views

struct DocumentRow: View {
    let document:      ScannedDocument
    let isLoadingView: Bool
    let onTap:         () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 40, height: 40)
                    if isLoadingView {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: document.type.iconName)
                            .font(.title3)
                            .foregroundStyle(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.fileName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(document.type.displayName)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.8), in: Capsule())

                        Text(document.formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !document.fileSizeFormatted.isEmpty {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(document.fileSizeFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let notes = document.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QuickLook wrapper

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
