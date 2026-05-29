import SwiftUI

// MARK: - View model

@MainActor
final class InvoicesViewModel: ObservableObject {
    @Published var invoices:      [Invoice] = []
    @Published var isLoading      = false
    @Published var errorMessage:  String?
    @Published var filterStatus:  String? = nil
    @Published var searchText     = ""

    var filtered: [Invoice] {
        let base: [Invoice]
        if let status = filterStatus {
            base = invoices.filter { $0.status == status }
        } else {
            base = invoices
        }
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
            invoices = try await APIService.shared.get("/invoices")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ invoice: Invoice) async {
        _ = try? await APIService.shared.delete("/invoices/\(invoice.id)")
        invoices.removeAll { $0.id == invoice.id }
    }
}

// MARK: - Main view

struct InvoicesListView: View {
    @StateObject private var vm = InvoicesViewModel()
    @State private var showNewInvoice = false

    private let statusFilters: [(String?, String)] = [
        (nil,         "All"),
        ("DRAFT",     "Draft"),
        ("SENT",      "Sent"),
        ("PAID",      "Paid"),
        ("OVERDUE",   "Overdue"),
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
                        if vm.isLoading && vm.invoices.isEmpty {
                            ProgressView("Loading invoices\u{2026}")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let err = vm.errorMessage {
                            ErrorView(message: err) { Task { await vm.load() } }
                        } else if vm.filtered.isEmpty {
                            EmptyStateView(
                                icon:    "chart.bar",
                                title:   "No Invoices",
                                message: vm.searchText.isEmpty
                                    ? "Create your first invoice using the + button."
                                    : "No results for \u{201C}\(vm.searchText)\u{201D}"
                            )
                        } else {
                            List {
                                ForEach(vm.filtered) { invoice in
                                    NavigationLink(value: invoice) {
                                        InvoiceRow(invoice: invoice)
                                    }
                                }
                                .onDelete { idx in
                                    let items = idx.map { vm.filtered[$0] }
                                    Task { for inv in items { await vm.delete(inv) } }
                                }
                            }
                            .listStyle(.plain)
                            .refreshable { await vm.load() }
                        }
                    }
                }
                .searchable(text: $vm.searchText, prompt: "Search invoices")
                .navigationTitle("Invoices")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Invoice.self) { invoice in
                    InvoiceDetailView(invoice: invoice) { updated in
                        if let idx = vm.invoices.firstIndex(where: { $0.id == updated.id }) {
                            vm.invoices[idx] = updated
                        }
                    }
                }
                .task { await vm.load() }

                // FAB
                if !showNewInvoice {
                    FABButton { showNewInvoice = true }
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: showNewInvoice)
        }
        .sheet(isPresented: $showNewInvoice, onDismiss: {
            Task { await vm.load() }
        }) {
            NewInvoiceSheet(isPresented: $showNewInvoice)
        }
    }
}

// MARK: - Invoice row

struct InvoiceRow: View {
    let invoice: Invoice

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
                    InvoiceStatusBadge(status: invoice.status)
                    Text(invoice.number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let due = invoice.dueDate, isOverdue(due) {
                        Text("· Overdue")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(invoice.total, format: .currency(code: "ZAR").presentation(.narrow))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(invoice.status == "PAID" ? Color.green : Color.primary)
                if let due = invoice.dueDate, !isOverdue(due) {
                    Text(shortDate(due))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var initials: String {
        guard let c = invoice.contact else {
            return invoice.projectName?.first.map { String($0).uppercased() } ?? "?"
        }
        let f = c.firstName?.first.map(String.init) ?? ""
        let l = c.lastName?.first.map(String.init) ?? ""
        let r = (f + l).uppercased()
        return r.isEmpty ? "?" : r
    }

    private var clientName: String {
        invoice.contact?.displayName ?? invoice.projectName ?? "No client"
    }

    private var statusColor: Color {
        switch invoice.status {
        case "SENT":      return Color(red: 0, green: 0.478, blue: 1)
        case "PAID":      return .green
        case "OVERDUE":   return Color(red: 1, green: 0.231, blue: 0.188)
        case "CANCELLED": return Color(.systemGray3)
        default:          return Color(.systemGray)
        }
    }

    private func shortDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        if let d = fmt.date(from: iso) {
            let out = DateFormatter()
            out.dateStyle = .medium
            return out.string(from: d)
        }
        return iso
    }

    private func isOverdue(_ iso: String) -> Bool {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        return fmt.date(from: iso).map { $0 < Date() } ?? false
    }
}

// MARK: - Status badge (invoices)

struct InvoiceStatusBadge: View {
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
        case "PAID":     return .green
        case "OVERDUE":  return .red
        case "CANCELLED": return .brandCTA
        default:         return .gray
        }
    }
}

// MARK: - Filter chip

struct FilterChip: View {
    let label:      String
    let isSelected: Bool
    var tint:       Color = .blue
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected ? tint : Color(.secondarySystemBackground),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - New invoice sheet

struct DraftItem: Identifiable {
    var id          = UUID()
    var description = ""
    var quantity:   String = "1"
    var unitPrice:  String = "0"
    var total: Double {
        (Double(quantity) ?? 0) * (Double(unitPrice) ?? 0)
    }
}

struct NewInvoiceSheet: View {
    @Binding var isPresented: Bool

    @State private var projectName   = ""
    @State private var notes         = ""
    @State private var dueDateOn     = false
    @State private var dueDate       = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var taxRate       = "15"
    @State private var items:        [DraftItem] = [DraftItem()]
    @State private var saving        = false
    @State private var error         = ""

    // Contact / company selection
    @State private var contacts:        [CRMContact] = []
    @State private var selectedContact: CRMContact?  = nil
    @State private var showContactPicker = false
    @State private var emailAllInCompany = false

    private var subtotal: Double { items.reduce(0) { $0 + $1.total } }
    private var tax: Double      { subtotal * ((Double(taxRate) ?? 0) / 100) }
    private var totalAmount: Double { subtotal + tax }

    private var isValid: Bool { !items.allSatisfy({ $0.description.isEmpty }) }

    // Contacts that share the selected contact's company
    private var companyContacts: [CRMContact] {
        guard let company = selectedContact?.companyName, !company.isEmpty else { return [] }
        return contacts.filter { $0.companyName == company && $0.id != selectedContact?.id }
    }

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
                                if let email = contact.email {
                                    Text(email).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Change") { showContactPicker = true }
                                .font(.caption.bold())
                                .foregroundStyle(.brand)
                        }

                        if !companyContacts.isEmpty {
                            Toggle(isOn: $emailAllInCompany) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Email all \(selectedContact!.companyName ?? "") contacts")
                                        .font(.subheadline)
                                    Text("\(companyContacts.count + 1) contacts will receive this invoice")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.brand)
                        }
                    } else {
                        Button { showContactPicker = true } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundStyle(.brand)
                                Text("Select a client (optional)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Project") {
                    TextField("Project name (optional)", text: $projectName)
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: $dueDateOn.animation())
                    if dueDateOn {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
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
                            .foregroundStyle(.blue)
                    }
                }

                Section("Notes") {
                    TextField("Internal notes (optional)", text: $notes, axis: .vertical)
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
            .navigationTitle("New Invoice")
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
            .task { await loadContacts() }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerSheet(
                    contacts: contacts,
                    onSelect: { contact in
                        selectedContact  = contact
                        emailAllInCompany = false
                        showContactPicker = false
                    },
                    onCancel: { showContactPicker = false }
                )
            }
        }
    }

    private func loadContacts() async {
        if let res: ContactsResponse = try? await APIService.shared.get("/crm/contacts") {
            contacts = res.contacts
        }
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
            let dueDateString: String? = dueDateOn
                ? ISO8601DateFormatter().string(from: dueDate)
                : nil
            let body = CreateInvoiceRequest(
                contactId:   selectedContact?.id,
                projectName: projectName.isEmpty ? nil : projectName.trimmingCharacters(in: .whitespaces),
                dueDate:     dueDateString,
                notes:       notes.isEmpty ? nil : notes,
                taxRate:     Double(taxRate) ?? 15,
                lineItems:   lineItems
            )
            let _: Invoice = try await APIService.shared.post("/invoices", body: body)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}

// MARK: - Contact picker sheet

struct ContactPickerSheet: View {
    let contacts: [CRMContact]
    let onSelect: (CRMContact) -> Void
    let onCancel: () -> Void

    @State private var search = ""

    // Group contacts by company
    private var grouped: [(company: String?, contacts: [CRMContact])] {
        var companies: [String: [CRMContact]] = [:]
        var noCompany: [CRMContact] = []
        for c in filtered {
            if let co = c.companyName, !co.isEmpty {
                companies[co, default: []].append(c)
            } else {
                noCompany.append(c)
            }
        }
        var result = companies.sorted { $0.key < $1.key }
            .map { (company: String?($0.key), contacts: $0.value) }
        if !noCompany.isEmpty {
            result.append((company: nil, contacts: noCompany))
        }
        return result
    }

    private var filtered: [CRMContact] {
        guard !search.isEmpty else { return contacts }
        let q = search.lowercased()
        return contacts.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.companyName?.lowercased().contains(q) == true)
            || ($0.email?.lowercased().contains(q) == true)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.company) { group in
                    Section(group.company ?? "Individual Contacts") {
                        ForEach(group.contacts) { contact in
                            Button { onSelect(contact) } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.brand.opacity(0.15))
                                            .frame(width: 36, height: 36)
                                        Text(contact.initials)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.brand)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(contact.displayName).font(.subheadline.bold())
                                        if let email = contact.email {
                                            Text(email).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search clients")
            .navigationTitle("Select Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

// MARK: - Draft line item row (used by NewInvoiceSheet & NewQuoteSheet)

struct DraftLineItemRow: View {
    @Binding var item: DraftItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Description", text: $item.description)
                .font(.subheadline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Qty").font(.caption2).foregroundStyle(.secondary)
                    TextField("1", text: $item.quantity)
                        .keyboardType(.decimalPad)
                        .font(.caption)
                        .frame(width: 52)
                        .padding(6)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unit price").font(.caption2).foregroundStyle(.secondary)
                    TextField("0.00", text: $item.unitPrice)
                        .keyboardType(.decimalPad)
                        .font(.caption)
                        .frame(width: 80)
                        .padding(6)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total").font(.caption2).foregroundStyle(.secondary)
                    Text(item.total, format: .currency(code: "ZAR"))
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Invoice detail

struct InvoiceDetailView: View {
    @State private var invoice: Invoice
    var onSaved: (Invoice) -> Void = { _ in }
    @State private var showEdit = false

    init(invoice: Invoice, onSaved: @escaping (Invoice) -> Void = { _ in }) {
        _invoice = State(initialValue: invoice)
        self.onSaved = onSaved
    }

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Invoice #", value: invoice.number)
                LabeledContent("Status") { InvoiceStatusBadge(status: invoice.status) }
                if let contact = invoice.contact {
                    LabeledContent("Contact", value: contact.displayName)
                }
                if let project = invoice.projectName {
                    LabeledContent("Project", value: project)
                }
                if let due = invoice.dueDate {
                    LabeledContent("Due Date", value: shortDate(due))
                }
            }

            if !invoice.lineItems.isEmpty {
                Section("Line Items") {
                    ForEach(invoice.lineItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.description).font(.subheadline)
                            HStack {
                                Text("\(item.quantity, specifier: "%.0f") × \(item.unitPrice, format: .currency(code: "ZAR"))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(item.total, format: .currency(code: "ZAR"))
                                    .font(.subheadline.bold())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Summary") {
                HStack { Text("Subtotal"); Spacer(); Text(invoice.subtotal, format: .currency(code: "ZAR")).foregroundStyle(.secondary) }
                if invoice.tax > 0 {
                    HStack { Text("Tax"); Spacer(); Text(invoice.tax, format: .currency(code: "ZAR")).foregroundStyle(.secondary) }
                }
                HStack {
                    Text("Total").bold()
                    Spacer()
                    Text(invoice.total, format: .currency(code: "ZAR")).bold()
                        .foregroundStyle(invoice.status == "PAID" ? .green : .primary)
                }
            }

            if let notes = invoice.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Invoice \(invoice.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }.fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showEdit) {
            EditInvoiceSheet(invoice: invoice, isPresented: $showEdit) { updated in
                invoice = updated
                onSaved(updated)
            }
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        guard let d = f.date(from: iso) else { return iso }
        return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
    }
}

// MARK: - Edit invoice sheet

struct EditInvoiceSheet: View {
    let invoice:    Invoice
    @Binding var isPresented: Bool
    let onSaved:    (Invoice) -> Void

    @State private var status:      String
    @State private var projectName: String
    @State private var notes:       String
    @State private var dueDateOn:   Bool
    @State private var dueDate:     Date
    @State private var taxRate:     String
    @State private var items:       [DraftItem]
    @State private var saving       = false
    @State private var error        = ""

    private let statuses = ["DRAFT", "SENT", "PAID", "OVERDUE", "CANCELLED"]

    init(invoice: Invoice, isPresented: Binding<Bool>, onSaved: @escaping (Invoice) -> Void) {
        self.invoice     = invoice
        self._isPresented = isPresented
        self.onSaved     = onSaved
        _status          = State(initialValue: invoice.status)
        _projectName     = State(initialValue: invoice.projectName ?? "")
        _notes           = State(initialValue: invoice.notes ?? "")
        _dueDateOn       = State(initialValue: invoice.dueDate != nil)
        let parsedDate: Date = {
            guard let s = invoice.dueDate else { return Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date() }
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            return f.date(from: s) ?? Date()
        }()
        _dueDate = State(initialValue: parsedDate)
        let rate: String = {
            guard invoice.subtotal > 0 else { return "15" }
            return String(format: "%.0f", (invoice.tax / invoice.subtotal) * 100)
        }()
        _taxRate = State(initialValue: rate)
        _items   = State(initialValue: invoice.lineItems.map {
            DraftItem(id: UUID(), description: $0.description,
                      quantity: String(format: "%g", $0.quantity),
                      unitPrice: String(format: "%g", $0.unitPrice))
        }.isEmpty ? [DraftItem()] : invoice.lineItems.map {
            DraftItem(id: UUID(), description: $0.description,
                      quantity: String(format: "%g", $0.quantity),
                      unitPrice: String(format: "%g", $0.unitPrice))
        })
    }

    private var subtotal: Double { items.reduce(0) { $0 + $1.total } }
    private var tax: Double      { subtotal * ((Double(taxRate) ?? 0) / 100) }
    private var totalAmt: Double { subtotal + tax }

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { s in
                            Text(s.capitalized).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Project") {
                    TextField("Project name (optional)", text: $projectName)
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: $dueDateOn.animation())
                    if dueDateOn {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Line Items") {
                    ForEach($items) { $item in DraftLineItemRow(item: $item) }
                        .onDelete { items.remove(atOffsets: $0) }
                    Button { withAnimation { items.append(DraftItem()) } } label: {
                        Label("Add line item", systemImage: "plus.circle").foregroundStyle(.brand)
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
                        Text(totalAmt, format: .currency(code: "ZAR")).fontWeight(.semibold).foregroundStyle(.blue) }
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(3)
                }

                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Edit Invoice")
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
            let dueDateStr: String? = dueDateOn ? ISO8601DateFormatter().string(from: dueDate) : nil
            let body = UpdateInvoiceRequest(
                status:      status,
                projectName: projectName.isEmpty ? nil : projectName.trimmingCharacters(in: .whitespaces),
                dueDate:     dueDateStr,
                notes:       notes.isEmpty ? nil : notes,
                taxRate:     Double(taxRate) ?? 15,
                lineItems:   lineItems.isEmpty ? nil : lineItems
            )
            let updated: Invoice = try await APIService.shared.put("/invoices/\(invoice.id)", body: body)
            onSaved(updated)
            isPresented = false
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}
