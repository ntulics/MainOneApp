import SwiftUI
import QuickLook
import UniformTypeIdentifiers

// MARK: - View model

@MainActor
final class DocumentsViewModel: ObservableObject {
    @Published var documents: [ScannedDocument] = []
    @Published var selectedType: DocumentType? = nil   // nil = all types
    @Published var isLoading    = false
    @Published var errorMessage: String?

    func load() async {
        isLoading    = true
        errorMessage = nil
        do {
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

// MARK: - File upload coordinator

@MainActor
final class FileUploadCoordinator: ObservableObject {
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var uploadedDoc: ScannedDocument?

    func upload(url: URL, type: DocumentType) async {
        isUploading  = true
        errorMessage = nil
        do {
            guard url.startAccessingSecurityScopedResource() else { throw URLError(.fileDoesNotExist) }
            defer { url.stopAccessingSecurityScopedResource() }
            let data     = try Data(contentsOf: url)
            let mimeType = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"
            uploadedDoc  = try await DocumentService.shared.uploadFile(
                data:     data,
                fileName: url.lastPathComponent,
                mimeType: mimeType,
                type:     type
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploading = false
    }
}

// MARK: - Main view

struct DocumentsView: View {
    var initialType: DocumentType? = nil

    @StateObject private var vm           = DocumentsViewModel()
    @StateObject private var uploader     = FileUploadCoordinator()
    @EnvironmentObject private var appState: AppState

    @State private var viewingDoc:    ScannedDocument?
    @State private var quickLookURL:  URL?
    @State private var showQuickLook  = false
    @State private var isLoadingDoc   = false
    @State private var viewError:     String?
    @State private var showViewError  = false
    @State private var hasSetInitial  = false

    @State private var showUploadPicker = false
    @State private var signingDoc:     ScannedDocument?

    // iPad split-view state
    private let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    @State private var selectedDoc: ScannedDocument? = nil

    var body: some View {
        if isIPad {
            iPadLayout
        } else {
            phoneLayout
        }
    }

    // MARK: - iPad split layout

    private var iPadLayout: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left: List
                VStack(spacing: 0) {
                    typeFilterBar
                    Divider()
                    documentListContent(onTap: { doc in selectedDoc = doc })
                }
                .frame(maxWidth: 360)

                Divider()

                // Right: Preview
                if let doc = selectedDoc {
                    iPadDocPreview(doc: doc)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Select a document to preview")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fileImporter(isPresented: $showUploadPicker,
                          allowedContentTypes: allowedUploadTypes,
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await uploader.upload(url: url, type: vm.selectedType ?? .general); await vm.load() }
                }
            }
            .sheet(item: $signingDoc) { doc in DocumentSigningView(document: doc) }
            .task {
                if !hasSetInitial { vm.selectedType = initialType; hasSetInitial = true }
                await vm.load()
            }
            .alert("Error", isPresented: $showViewError) { Button("OK") {} }
                message: { Text(viewError ?? "Could not open document.") }
        }
    }

    // MARK: - iPhone layout

    private var phoneLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                typeFilterBar
                Divider()
                documentListContent { doc in Task { await openDocument(doc) } }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showQuickLook, onDismiss: cleanupTempFile) {
                if let url = quickLookURL { QuickLookPreview(url: url).ignoresSafeArea() }
            }
            .fileImporter(isPresented: $showUploadPicker,
                          allowedContentTypes: allowedUploadTypes,
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await uploader.upload(url: url, type: vm.selectedType ?? .general); await vm.load() }
                }
            }
            .sheet(item: $signingDoc) { doc in DocumentSigningView(document: doc) }
            .task {
                if !hasSetInitial { vm.selectedType = initialType; hasSetInitial = true }
                await vm.load()
            }
            .alert("Error", isPresented: $showViewError) { Button("OK") {} }
                message: { Text(viewError ?? "Could not open document.") }
        }
    }

    // MARK: - iPad document preview panel

    @ViewBuilder
    private func iPadDocPreview(doc: ScannedDocument) -> some View {
        VStack(spacing: 0) {
            // Toolbar for preview actions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.fileName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(doc.type.displayName + " · " + doc.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    signingDoc = doc
                } label: {
                    Label("Sign", systemImage: "signature")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.brand.opacity(0.15), in: Capsule())
                        .foregroundStyle(.brand)
                }
                Button { Task { await loadAndShowPreview(doc) } } label: {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            Divider()

            // QuickLook inline preview
            if isLoadingDoc {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = quickLookURL, viewingDoc?.id == doc.id {
                QuickLookPreview(url: url)
            } else {
                Button { Task { await loadAndShowPreview(doc) } } label: {
                    VStack(spacing: 16) {
                        Image(systemName: doc.type.iconName)
                            .font(.system(size: 56))
                            .foregroundStyle(.brand)
                        Text("Tap to load preview")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(doc.fileSizeFormatted)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showQuickLook, onDismiss: cleanupTempFile) {
            if let url = quickLookURL { QuickLookPreview(url: url).ignoresSafeArea() }
        }
        .onChange(of: doc.id) { _ in
            quickLookURL  = nil
            viewingDoc    = nil
        }
    }

    // MARK: - Type filter bar

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: vm.selectedType == nil, tint: .brand) {
                    vm.selectedType = nil
                    Task { await vm.load() }
                }
                ForEach(DocumentType.allCases, id: \.self) { type in
                    FilterChip(label: type.displayName, isSelected: vm.selectedType == type, tint: .brand) {
                        vm.selectedType = type
                        Task { await vm.load() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Document list

    @ViewBuilder
    private func documentListContent(onTap: @escaping (ScannedDocument) -> Void) -> some View {
        Group {
            if vm.isLoading && vm.documents.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.brand)
                    Text(err).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await vm.load() } }
                        .buttonStyle(.borderedProminent).tint(.brand)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.documents.isEmpty {
                EmptyStateView(
                    icon:    "folder",
                    title:   "No Documents",
                    message: vm.selectedType == nil
                        ? "Scan or upload documents to get started."
                        : "No \(vm.selectedType!.displayName.lowercased()) documents yet."
                )
            } else {
                List {
                    ForEach(vm.documents) { doc in
                        DocumentRow(
                            document:      doc,
                            isLoadingView: isLoadingDoc && viewingDoc?.id == doc.id,
                            onSign:        { signingDoc = doc },
                            onTap:         { onTap(doc) }
                        )
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Scan button (only for scannable types)
        if let type = vm.selectedType, [DocumentType.receipt, .vendorQuote, .general].contains(type) {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.scannerType = type
                    appState.showScanner = true
                } label: {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tint(.brand)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button { showUploadPicker = true } label: {
                Label("Upload", systemImage: "arrow.up.doc")
            }
            .tint(.brand)
        }
    }

    // MARK: - Allowed upload types

    private var allowedUploadTypes: [UTType] {
        vm.selectedType == .invoice ? [.pdf] : [.pdf, .jpeg, .png, .image]
    }

    // MARK: - Navigation title

    private var navigationTitle: String {
        guard let type = vm.selectedType else { return "Documents" }
        return type.displayName
    }

    // MARK: - Helpers

    private func openDocument(_ doc: ScannedDocument) async {
        viewingDoc   = doc
        isLoadingDoc = true
        do {
            quickLookURL = try await DocumentService.shared.viewDocument(doc)
            showQuickLook = true
        } catch {
            viewError     = error.localizedDescription
            showViewError = true
        }
        isLoadingDoc = false
        viewingDoc   = nil
    }

    private func loadAndShowPreview(_ doc: ScannedDocument) async {
        viewingDoc   = doc
        isLoadingDoc = true
        quickLookURL = try? await DocumentService.shared.viewDocument(doc)
        isLoadingDoc = false
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
    var onSign:        (() -> Void)? = nil
    let onTap:         () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.brand.opacity(0.1))
                            .frame(width: 40, height: 40)
                        if isLoadingView {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Image(systemName: document.type.iconName)
                                .font(.title3)
                                .foregroundStyle(.brand)
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
                                .background(Color.brand.opacity(0.8), in: Capsule())

                            Text(document.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !document.fileSizeFormatted.isEmpty {
                                Text("·").foregroundStyle(.secondary)
                                Text(document.fileSizeFormatted)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        if let notes = document.notes, !notes.isEmpty {
                            Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Sign button
            if let sign = onSign {
                Button(action: sign) {
                    Image(systemName: "signature")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.brand)
                        .frame(width: 32, height: 32)
                        .background(Color.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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
