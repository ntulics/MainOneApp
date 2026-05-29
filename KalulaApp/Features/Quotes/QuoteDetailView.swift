import SwiftUI

// MARK: - Quote detail

struct QuoteDetailView: View {
    @State private var quote: Quote
    @State private var showEdit = false

    init(quote: Quote) {
        _quote = State(initialValue: quote)
    }

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Quote #", value: quote.number)
                LabeledContent("Status") { StatusBadge(status: quote.status) }
                if let contact = quote.contact {
                    LabeledContent("Contact", value: contact.displayName)
                }
                if let project = quote.projectName {
                    LabeledContent("Project", value: project)
                }
                if let validUntil = quote.validUntil {
                    LabeledContent("Valid Until", value: formattedDate(validUntil))
                }
            }

            if !quote.lineItems.isEmpty {
                Section("Line Items") {
                    ForEach(quote.lineItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.description).font(.subheadline)
                            HStack {
                                Text("\(item.quantity, specifier: "%.0f") × \(item.unitPrice, format: .currency(code: "ZAR"))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(item.total, format: .currency(code: "ZAR")).font(.subheadline.bold())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Summary") {
                HStack { Text("Subtotal"); Spacer(); Text(quote.subtotal, format: .currency(code: "ZAR")).foregroundStyle(.secondary) }
                if quote.tax > 0 {
                    HStack { Text("Tax"); Spacer(); Text(quote.tax, format: .currency(code: "ZAR")).foregroundStyle(.secondary) }
                }
                HStack {
                    Text("Total").bold()
                    Spacer()
                    Text(quote.total, format: .currency(code: "ZAR")).bold()
                        .foregroundStyle(quote.status == "ACCEPTED" ? .green : Color.brand)
                }
            }

            if let notes = quote.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Quote \(quote.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }.fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showEdit) {
            EditQuoteSheet(quote: quote, isPresented: $showEdit) { updated in
                quote = updated
            }
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) else { return iso }
        return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
    }
}

// MARK: - Edit quote sheet

struct EditQuoteSheet: View {
    let quote:        Quote
    @Binding var isPresented: Bool
    let onSaved:      (Quote) -> Void

    @State private var status:       String
    @State private var projectName:  String
    @State private var notes:        String
    @State private var validUntilOn: Bool
    @State private var validUntil:   Date
    @State private var taxRate:      String
    @State private var items:        [DraftItem]
    @State private var saving        = false
    @State private var error         = ""

    private let statuses = ["DRAFT", "SENT", "ACCEPTED", "DECLINED", "EXPIRED"]

    init(quote: Quote, isPresented: Binding<Bool>, onSaved: @escaping (Quote) -> Void) {
        self.quote        = quote
        self._isPresented = isPresented
        self.onSaved      = onSaved
        _status           = State(initialValue: quote.status)
        _projectName      = State(initialValue: quote.projectName ?? "")
        _notes            = State(initialValue: quote.notes ?? "")
        _validUntilOn     = State(initialValue: quote.validUntil != nil)
        let parsedDate: Date = {
            guard let s = quote.validUntil else { return Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date() }
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            return f.date(from: s) ?? Date()
        }()
        _validUntil = State(initialValue: parsedDate)
        let rate: String = {
            guard quote.subtotal > 0 else { return "15" }
            return String(format: "%.0f", (quote.tax / quote.subtotal) * 100)
        }()
        _taxRate = State(initialValue: rate)
        let draftItems = quote.lineItems.map {
            DraftItem(id: UUID(), description: $0.description,
                      quantity: String(format: "%g", $0.quantity),
                      unitPrice: String(format: "%g", $0.unitPrice))
        }
        _items = State(initialValue: draftItems.isEmpty ? [DraftItem()] : draftItems)
    }

    private var subtotal: Double { items.reduce(0) { $0 + $1.total } }
    private var tax: Double      { subtotal * ((Double(taxRate) ?? 0) / 100) }
    private var totalAmt: Double { subtotal + tax }

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { s in Text(s.capitalized).tag(s) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Project") {
                    TextField("Project name (optional)", text: $projectName)
                }

                Section("Validity") {
                    Toggle("Set expiry date", isOn: $validUntilOn.animation())
                    if validUntilOn {
                        DatePicker("Valid until", selection: $validUntil, displayedComponents: .date)
                    }
                }

                Section("Line Items") {
                    ForEach($items) { $item in DraftLineItemRow(item: $item) }
                        .onDelete { items.remove(atOffsets: $0) }
                    Button { withAnimation { items.append(DraftItem()) } } label: {
                        Label("Add line item", systemImage: "plus.circle").foregroundStyle(Color.brand)
                    }
                }

                Section("Tax & Total") {
                    HStack {
                        Text("Tax rate (%)")
                        Spacer()
                        TextField("15", text: $taxRate).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 60)
                    }
                    HStack { Text("Subtotal"); Spacer(); Text(subtotal, format: .currency(code: "ZAR")).foregroundStyle(.secondary) }
                    HStack { Text("Tax");      Spacer(); Text(tax,      format: .currency(code: "ZAR")).foregroundStyle(.secondary) }
                    HStack { Text("Total").fontWeight(.semibold); Spacer()
                        Text(totalAmt, format: .currency(code: "ZAR")).fontWeight(.semibold).foregroundStyle(Color.brand) }
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(3)
                }

                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Edit Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(saving)
                }
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        do {
            let lineItems = items.filter { !$0.description.isEmpty }.map {
                CreateLineItem(description: $0.description.trimmingCharacters(in: .whitespaces),
                               quantity: Double($0.quantity) ?? 1,
                               unitPrice: Double($0.unitPrice) ?? 0,
                               total: $0.total)
            }
            let validUntilStr: String? = validUntilOn ? ISO8601DateFormatter().string(from: validUntil) : nil
            let body = UpdateQuoteRequest(
                status:      status,
                projectName: projectName.isEmpty ? nil : projectName.trimmingCharacters(in: .whitespaces),
                validUntil:  validUntilStr,
                notes:       notes.isEmpty ? nil : notes,
                taxRate:     Double(taxRate) ?? 15,
                lineItems:   lineItems.isEmpty ? nil : lineItems
            )
            let updated: Quote = try await APIService.shared.put("/quotes/\(quote.id)", body: body)
            onSaved(updated)
            isPresented = false
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}
