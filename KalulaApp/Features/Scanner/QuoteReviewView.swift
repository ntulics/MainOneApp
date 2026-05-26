import SwiftUI

struct QuoteReviewView: View {
    let parsed: ParsedQuote
    let onCreateQuote: ([ParsedLineItem]) -> Void
    let onSkip: () -> Void

    @State private var lineItems: [ParsedLineItem]
    @State private var projectName: String
    @State private var notes: String

    init(parsed: ParsedQuote, onCreateQuote: @escaping ([ParsedLineItem]) -> Void, onSkip: @escaping () -> Void) {
        self.parsed = parsed
        self.onCreateQuote = onCreateQuote
        self.onSkip = onSkip
        _lineItems = State(initialValue: parsed.lineItems)
        _projectName = State(initialValue: parsed.projectName ?? "")
        _notes = State(initialValue: parsed.notes ?? "")
    }

    var body: some View {
        List {
            // Vendor info
            if let vendor = parsed.vendorName {
                Section("Vendor") {
                    Label(vendor, systemImage: "building.2")
                }
            }

            Section("Project Name") {
                TextField("Project name", text: $projectName)
            }

            // Line items — editable
            Section {
                ForEach($lineItems) { $item in
                    LineItemRow(item: $item)
                }
                .onDelete { lineItems.remove(atOffsets: $0) }

                Button {
                    lineItems.append(ParsedLineItem(description: "", quantity: 1, unitPrice: 0, total: 0))
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            } header: {
                HStack {
                    Text("Line Items")
                    Spacer()
                    Text("\(lineItems.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Totals (read-only summary)
            Section("Totals") {
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(subtotal, format: .currency(code: parsed.currency ?? "ZAR"))
                }
                if let tax = parsed.tax, tax > 0 {
                    HStack {
                        Text("Tax")
                        Spacer()
                        Text(tax, format: .currency(code: parsed.currency ?? "ZAR"))
                    }
                    HStack {
                        Text("Total")
                            .bold()
                        Spacer()
                        Text(subtotal + tax, format: .currency(code: parsed.currency ?? "ZAR"))
                            .bold()
                    }
                }
            }

            if !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Review Quote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create Quote") {
                    onCreateQuote(lineItems)
                }
                .fontWeight(.semibold)
                .tint(.orange)
                .disabled(lineItems.isEmpty)
            }

            ToolbarItem(placement: .topBarLeading) {
                Button("Skip") { onSkip() }
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.total }
    }
}

struct LineItemRow: View {
    @Binding var item: ParsedLineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Description", text: $item.description)
                .font(.subheadline)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Qty").font(.caption2).foregroundStyle(.secondary)
                    TextField("1", value: $item.quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 60)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unit Price").font(.caption2).foregroundStyle(.secondary)
                    TextField("0.00", value: $item.unitPrice, format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 90)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total").font(.caption2).foregroundStyle(.secondary)
                    Text(item.quantity * item.unitPrice, format: .currency(code: "ZAR"))
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: item.quantity) { _ in item.total = item.quantity * item.unitPrice }
        .onChange(of: item.unitPrice) { _ in item.total = item.quantity * item.unitPrice }
    }
}
