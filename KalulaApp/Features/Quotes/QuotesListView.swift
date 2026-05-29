import SwiftUI
import UniformTypeIdentifiers

// MARK: - View model

@MainActor
final class QuotesViewModel: ObservableObject {
    @Published var quotes:        [Quote] = []
    @Published var isLoading      = false
    @Published var errorMessage:  String?
    @Published var filterStatus:  String? = nil
    @Published var searchText     = ""

    var filtered: [Quote] {
        let base: [Quote] = filterStatus == nil
            ? quotes
            : quotes.filter { $0.status == filterStatus }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.number.lowercased().contains(q)
            || ($0.projectName?.lowercased().contains(q) == true)
            || ($0.contact?.displayName.lowercased().contains(q) == true)
        }
    }

    func load() async {
        isLoading    = true
        errorMessage = nil
        do {
            quotes = try await APIService.shared.get("/quotes")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ quote: Quote) async {
        _ = try? await APIService.shared.delete("/quotes/\(quote.id)")
        quotes.removeAll { $0.id == quote.id }
    }
}

// MARK: - Main view

struct QuotesListView: View {
    @StateObject private var vm = QuotesViewModel()
    @State private var showNewQuote = false

    private let statusFilters: [(String?, String)] = [
        (nil,        "All"),
        ("DRAFT",    "Draft"),
        ("SENT",     "Sent"),
        ("ACCEPTED", "Accepted"),
        ("DECLINED", "Declined"),
        ("EXPIRED",  "Expired"),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Status filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(statusFilters, id: \.0) { filter in
                                FilterChip(
                                    label:      filter.1,
                                    isSelected: vm.filterStatus == filter.0,
                                    tint:       .brand
                                ) {
                                    vm.filterStatus = filter.0
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(Color(.systemBackground))

                    Divider()

                    Group {
                        if vm.isLoading && vm.quotes.isEmpty {
                            ProgressView("Loading quotes\u{2026}")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let err = vm.errorMessage {
                            ErrorView(message: err) { Task { await vm.load() } }
                        } else if vm.filtered.isEmpty {
                            EmptyStateView(
                                icon:    "doc.text",
                                title:   "No Quotes",
                                message: vm.searchText.isEmpty
                                    ? "Create a quote using the + button or scan a vendor document."
                                    : "No results for \u{201C}\(vm.searchText)\u{201D}"
                            )
                        } else {
                            List {
                                ForEach(vm.filtered) { quote in
                                    NavigationLink(value: quote) {
                                        QuoteRow(quote: quote)
                                    }
                                }
                                .onDelete { indices in
                                    let items = indices.map { vm.filtered[$0] }
                                    Task { for q in items { await vm.delete(q) } }
                                }
                            }
                            .listStyle(.plain)
                            .refreshable { await vm.load() }
                        }
                    }
                }
                .searchable(text: $vm.searchText, prompt: "Search quotes")
                .navigationTitle("Quotes")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Quote.self) { QuoteDetailView(quote: $0) }
                .task { await vm.load() }

                // FAB
                if !showNewQuote {
                    FABButton { showNewQuote = true }
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: showNewQuote)
        }
        .sheet(isPresented: $showNewQuote, onDismiss: {
            Task { await vm.load() }
        }) {
            NewQuoteSheet(isPresented: $showNewQuote)
        }
    }
}

// MARK: - Quote row

struct QuoteRow: View {
    let quote: Quote

    var body: some View {
        HStack(spacing: 14) {
            // Initials avatar
            Circle()
                .fill(statusColor.opacity(0.12))
                .frame(width: 46, height: 46)
                .overlay(
                    Text(initials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(statusColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(clientName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    StatusBadge(status: quote.status)
                    Text(quote.number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let valid = quote.validUntil {
                        Text("· \(shortDate(valid))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(quote.total, format: .currency(code: "ZAR").presentation(.narrow))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(quote.status == "ACCEPTED" ? Color.green : Color.primary)
        }
        .padding(.vertical, 8)
    }

    private var initials: String {
        guard let c = quote.contact else {
            return quote.projectName?.first.map { String($0).uppercased() } ?? "?"
        }
        let f = c.firstName?.first.map(String.init) ?? ""
        let l = c.lastName?.first.map(String.init) ?? ""
        let r = (f + l).uppercased()
        return r.isEmpty ? "?" : r
    }

    private var clientName: String {
        quote.contact?.displayName ?? quote.projectName ?? "No client"
    }

    private var statusColor: Color {
        switch quote.status {
        case "SENT":     return Color(red: 0, green: 0.478, blue: 1)
        case "ACCEPTED": return .green
        case "DECLINED": return Color(red: 1, green: 0.231, blue: 0.188)
        case "EXPIRED":  return Color(red: 1, green: 0.584, blue: 0)
        default:         return Color(.systemGray)
        }
    }

    private func shortDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        guard let d = fmt.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }
}

// MARK: - Status badge

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch status {
        case "DRAFT":    return .gray
        case "SENT":     return .blue
        case "ACCEPTED": return .green
        case "DECLINED": return .red
        case "EXPIRED":  return .brandCTA
        default:         return .gray
        }
    }
}

// MARK: - New quote sheet

struct NewQuoteSheet: View {
    @Binding var isPresented: Bool

    @State private var projectName  = ""
    @State private var notes        = ""
    @State private var validUntilOn = false
    @State private var validUntil   = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var taxRate      = "15"
    @State private var items:       [DraftItem] = [DraftItem()]
    @State private var saving       = false
    @State private var error        = ""
    @State private var showScanner      = false
    @State private var showUploadPicker = false
    @State private var isParsing        = false
    @State private var parseError:      String?
    @State private var showParseError   = false
    @State private var uploadedDocId:   String?   // sourceDocumentId for the created quote

    // Contact selection
    @State private var contacts:        [CRMContact] = []
    @State private var selectedContact: CRMContact?  = nil
    @State private var showContactPicker = false

    private var subtotal: Double    { items.reduce(0) { $0 + $1.total } }
    private var tax: Double         { subtotal * ((Double(taxRate) ?? 0) / 100) }
    private var totalAmount: Double { subtotal + tax }
    private var isValid: Bool       { !items.allSatisfy({ $0.description.isEmpty }) }

    var body: some View {
        NavigationStack {
            Form {
                // ── Client ─────────────────────────────────────────────────
                Section("Client") {
                    if let contact = selectedContact {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.displayName).font(.subheadline.bold())
                                if let company = contact.companyName, !company.isEmpty {
                                    Text(company).font(.caption).foregroundStyle(.brand)
                                }
                            }
                            Spacer()
                            Button("Change") { showContactPicker = true }
                                .font(.caption.bold()).foregroundStyle(.brand)
                        }
                    } else {
                        Button { showContactPicker = true } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(.brand)
                                Text("Select a client (optional)").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button { showScanner = true } label: {
                        Label("Scan Vendor Quote", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity).foregroundStyle(.brand)
                    }
                    Button { showUploadPicker = true } label: {
                        Label("Upload Document", systemImage: "arrow.up.doc")
                            .frame(maxWidth: .infinity).foregroundStyle(.brand)
                    }
                } footer: {
                    Text("Scan or upload a vendor quote to auto-fill line items.")
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
                    ForEach($items) { $item in
                        DraftLineItemRow(item: $item)
                    }
                    .onDelete { items.remove(atOffsets: $0) }

                    Button {
                        withAnimation { items.append(DraftItem()) }
                    } label: {
                        Label("Add line item", systemImage: "plus.circle")
                            .foregroundStyle(.brand)
                    }
                }

                Section("Tax & Total") {
                    HStack {
                        Text("Tax rate (%)")
                        Spacer()
                        TextField("15", text: $taxRate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    HStack {
                        Text("Subtotal")
                        Spacer()
                        Text(subtotal, format: .currency(code: "ZAR"))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Tax")
                        Spacer()
                        Text(tax, format: .currency(code: "ZAR"))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Total")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(totalAmount, format: .currency(code: "ZAR"))
                            .fontWeight(.semibold)
                            .foregroundStyle(.brand)
                    }
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }

                if !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(!isValid || saving)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScannerView(initialType: .vendorQuote, onScanned: { parsed in
                    projectName = parsed.projectName ?? projectName
                    notes       = parsed.notes       ?? notes
                    if !parsed.lineItems.isEmpty {
                        items = parsed.lineItems.map { li in
                            var d = DraftItem()
                            d.description = li.description
                            d.quantity    = String(format: "%g", li.quantity)
                            d.unitPrice   = String(format: "%g", li.unitPrice)
                            return d
                        }
                    }
                    showScanner = false
                })
            }
            .fileImporter(
                isPresented: $showUploadPicker,
                allowedContentTypes: [.pdf, .jpeg, .png, .image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await handleUploadedDoc(url: url) }
                }
            }
            .task { await loadContacts() }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerSheet(
                    contacts: contacts,
                    onSelect: { contact in selectedContact = contact; showContactPicker = false },
                    onCancel: { showContactPicker = false }
                )
            }
            .alert("Could not parse document", isPresented: $showParseError) {
                Button("OK") {}
            } message: {
                Text(parseError ?? "The document could not be read. You can still fill in the details manually.")
            }
            .overlay {
                if isParsing {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.4).tint(.white)
                            Text("Reading vendor quote…")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text("Extracting line items")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
        }
    }

    private func loadContacts() async {
        if let res: ContactsResponse = try? await APIService.shared.get("/crm/contacts") {
            contacts = res.contacts
        }
    }

    private func handleUploadedDoc(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let mimeType = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"

        isParsing = true
        do {
            // OCR + AI parse → pre-populate form
            let parsed = try await DocumentService.shared.parseVendorQuoteFromData(data, mimeType: mimeType)

            if let name = parsed.projectName, !name.isEmpty { projectName = name }
            if let n    = parsed.notes,       !n.isEmpty    { notes = n }
            if !parsed.lineItems.isEmpty {
                items = parsed.lineItems.map { li in
                    var d = DraftItem()
                    d.description = li.description
                    d.quantity    = String(format: "%g", li.quantity)
                    d.unitPrice   = String(format: "%g", li.unitPrice)
                    return d
                }
            }

            // Upload original file to document storage in background
            let doc = try? await DocumentService.shared.uploadFile(
                data: data, fileName: url.lastPathComponent,
                mimeType: mimeType, type: .vendorQuote
            )
            uploadedDocId = doc?.id
        } catch {
            parseError     = error.localizedDescription
            showParseError = true
        }
        isParsing = false
    }

    private func save() async {
        saving = true
        error  = ""
        do {
            let lineItems = items
                .filter { !$0.description.isEmpty }
                .map {
                    CreateLineItem(
                        description: $0.description.trimmingCharacters(in: .whitespaces),
                        quantity:    Double($0.quantity)  ?? 1,
                        unitPrice:   Double($0.unitPrice) ?? 0,
                        total:       $0.total
                    )
                }
            let validUntilString: String? = validUntilOn
                ? ISO8601DateFormatter().string(from: validUntil)
                : nil
            let body = CreateMobileQuoteRequest(
                contactId:   selectedContact?.id,
                projectName: projectName.isEmpty ? nil : projectName.trimmingCharacters(in: .whitespaces),
                validUntil:  validUntilString,
                notes:       notes.isEmpty ? nil : notes,
                taxRate:     Double(taxRate) ?? 15,
                lineItems:   lineItems
            )
            let _: Quote = try await APIService.shared.post("/quotes", body: body)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}
