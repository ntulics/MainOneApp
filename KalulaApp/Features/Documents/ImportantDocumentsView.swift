import SwiftUI

struct ImportantDocumentsView: View {
    @EnvironmentObject private var appState: AppState

    private let sections: [(title: String, subtitle: String, icon: String, color: Color)] = [
        ("Company Documents",  "Registration, certificates & licences",  "building.2.fill",      .yellow),
        ("Contracts",          "Agreements, NDAs & signed documents",     "doc.text.fill",        .indigo),
        ("Tax & Compliance",   "Tax returns, SARS correspondence & FICA", "doc.badge.gearshape",  .teal),
        ("Insurance",          "Policies & claim documents",              "shield.checkered",     .green),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(sections, id: \.title) { section in
                        ImportantSectionRow(
                            title:    section.title,
                            subtitle: section.subtitle,
                            icon:     section.icon,
                            color:    section.color
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Important")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Section row

private struct ImportantSectionRow: View {
    let title:    String
    let subtitle: String
    let icon:     String
    let color:    Color

    var body: some View {
        NavigationLink(destination: ImportantDocumentListView(title: title)) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 56, height: 56)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Document list for an Important sub-category

private struct ImportantDocumentListView: View {
    let title: String

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm      = ImportantDocListVM()
    @State private var showUpload    = false
    @State private var signingDoc:   ScannedDocument? = nil
    @State private var quickLookURL: URL?
    @State private var showQuickLook = false
    @State private var isLoadingDoc  = false
    @State private var viewingDoc:   ScannedDocument? = nil

    private let isIPad = UIDevice.current.userInterfaceIdiom == .pad

    var body: some View {
        Group {
            if isIPad {
                iPadLayout
            } else {
                phoneLayout
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showUpload = true } label: {
                    Label("Upload", systemImage: "arrow.up.doc")
                }
                .tint(.orange)
            }
        }
        .fileImporter(
            isPresented: $showUpload,
            allowedContentTypes: [.pdf, .jpeg, .png, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await vm.upload(url: url); await vm.load() }
            }
        }
        .sheet(item: $signingDoc) { doc in DocumentSigningView(document: doc) }
        .sheet(isPresented: $showQuickLook, onDismiss: cleanupTemp) {
            if let url = quickLookURL { QuickLookPreview(url: url).ignoresSafeArea() }
        }
        .task { await vm.load() }
    }

    // MARK: iPad split

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                docList { doc in vm.selectedDoc = doc }
            }
            .frame(maxWidth: 360)

            Divider()

            if let doc = vm.selectedDoc {
                iPadPreview(doc: doc)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48)).foregroundStyle(.tertiary)
                    Text("Select a document to preview")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: iPhone layout

    private var phoneLayout: some View {
        docList { doc in Task { await openDoc(doc) } }
    }

    // MARK: Document list

    @ViewBuilder
    private func docList(onTap: @escaping (ScannedDocument) -> Void) -> some View {
        if vm.isLoading && vm.documents.isEmpty {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle).foregroundStyle(.orange)
                Text(err).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.orange)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.documents.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 52)).foregroundStyle(Color(.systemGray4))
                Text("No documents yet")
                    .font(.title3.bold()).foregroundStyle(.secondary)
                Text("Tap Upload to add your first document.")
                    .font(.subheadline).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Button { showUpload = true } label: {
                    Label("Upload Document", systemImage: "arrow.up.doc")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
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
                .onDelete { idx in
                    let items = idx.map { vm.documents[$0] }
                    Task { for d in items { await vm.delete(d) } }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    // MARK: iPad inline preview

    @ViewBuilder
    private func iPadPreview(doc: ScannedDocument) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.fileName).font(.headline).lineLimit(1)
                    Text(doc.formattedDate).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { signingDoc = doc } label: {
                    Label("Sign", systemImage: "signature")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Button { Task { await loadPreview(doc) } } label: {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            Divider()

            if isLoadingDoc {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = quickLookURL, viewingDoc?.id == doc.id {
                QuickLookPreview(url: url)
            } else {
                Button { Task { await loadPreview(doc) } } label: {
                    VStack(spacing: 16) {
                        Image(systemName: doc.type.iconName)
                            .font(.system(size: 56)).foregroundStyle(.orange)
                        Text("Tap to load preview").font(.subheadline).foregroundStyle(.secondary)
                        Text(doc.fileSizeFormatted).font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showQuickLook, onDismiss: cleanupTemp) {
            if let url = quickLookURL { QuickLookPreview(url: url).ignoresSafeArea() }
        }
        .onChange(of: doc.id) { _ in quickLookURL = nil; viewingDoc = nil }
    }

    // MARK: Helpers

    private func openDoc(_ doc: ScannedDocument) async {
        viewingDoc = doc; isLoadingDoc = true
        quickLookURL = try? await DocumentService.shared.viewDocument(doc)
        isLoadingDoc = false; showQuickLook = true
    }

    private func loadPreview(_ doc: ScannedDocument) async {
        viewingDoc = doc; isLoadingDoc = true
        quickLookURL = try? await DocumentService.shared.viewDocument(doc)
        isLoadingDoc = false
    }

    private func cleanupTemp() {
        if let url = quickLookURL { try? FileManager.default.removeItem(at: url); quickLookURL = nil }
    }
}

// MARK: - View model for Important list

@MainActor
private final class ImportantDocListVM: ObservableObject {
    @Published var documents:    [ScannedDocument] = []
    @Published var selectedDoc:  ScannedDocument?  = nil
    @Published var isLoading     = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true; errorMessage = nil
        do {
            documents = try await DocumentService.shared.getDocuments(type: .important)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ doc: ScannedDocument) async {
        try? await DocumentService.shared.deleteDocument(id: doc.id)
        documents.removeAll { $0.id == doc.id }
        if selectedDoc?.id == doc.id { selectedDoc = nil }
    }

    func upload(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data     = try Data(contentsOf: url)
            let mimeType = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"
            _ = try await DocumentService.shared.uploadFile(
                data: data, fileName: url.lastPathComponent, mimeType: mimeType, type: .important
            )
        } catch {}
    }
}
