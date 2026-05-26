import SwiftUI

struct ReceiptsView: View {
    @StateObject private var vm = ReceiptsViewModel()
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.receipts.isEmpty {
                    ProgressView("Loading receipts…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.receipts.isEmpty {
                    EmptyStateView(icon: "receipt", title: "No Receipts", message: "Scan receipts to store them for accounting records.")
                } else {
                    List {
                        ForEach(vm.receipts) { receipt in
                            ReceiptRow(receipt: receipt)
                        }
                        .onDelete { indices in
                            let items = indices.map { vm.receipts[$0] }
                            Task { for r in items { await vm.delete(r) } }
                        }
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Receipts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner, onDismiss: {
                Task { await vm.load() }
            }) {
                ScannerView(initialType: .receipt)
            }
            .task { await vm.load() }
        }
    }
}

@MainActor
final class ReceiptsViewModel: ObservableObject {
    @Published var receipts: [ScannedDocument] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        receipts = (try? await DocumentService.shared.getDocuments(type: .receipt)) ?? []
        isLoading = false
    }

    func delete(_ doc: ScannedDocument) async {
        try? await DocumentService.shared.deleteDocument(id: doc.id)
        receipts.removeAll { $0.id == doc.id }
    }
}

struct ReceiptRow: View {
    let receipt: ScannedDocument

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "receipt")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 40, height: 40)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.fileName)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(receipt.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let amount = receipt.metadata?.amount {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(amount, format: .currency(code: receipt.metadata?.currency ?? "ZAR"))
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }

                if let notes = receipt.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let vendor = receipt.metadata?.vendor {
                Text(vendor)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 4)
    }
}
