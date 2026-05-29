import SwiftUI

// MARK: - View model

@MainActor
final class CustomersViewModel: ObservableObject {
    @Published var contacts:  [CRMContact] = []
    @Published var isLoading  = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    var filtered: [CRMContact] {
        guard !searchText.isEmpty else { return contacts }
        let q = searchText.lowercased()
        return contacts.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.email?.lowercased().contains(q) == true)
            || ($0.phone?.contains(q) == true)
        }
    }

    func load() async {
        isLoading    = true
        errorMessage = nil
        do {
            let res: ContactsResponse = try await APIService.shared.get("/crm/contacts")
            contacts = res.contacts
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ contact: CRMContact) async {
        _ = try? await APIService.shared.delete("/crm/contacts/\(contact.id)")
        contacts.removeAll { $0.id == contact.id }
    }
}

// MARK: - Main view

struct CustomersView: View {
    @StateObject private var vm = CustomersViewModel()
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showNewContact      = false
    @State private var selectedTab         = 0
    @State private var selectedContact:     CRMContact? = nil
    @State private var selectedCompanyName: String?     = nil

    private var companies: [(name: String, contacts: [CRMContact])] {
        var map: [String: [CRMContact]] = [:]
        for c in vm.contacts {
            guard let co = c.companyName, !co.isEmpty else { continue }
            map[co, default: []].append(c)
        }
        return map.sorted { $0.key < $1.key }.map { (name: $0.key, contacts: $0.value) }
    }

    private var selectedCompanyContacts: [CRMContact] {
        guard let name = selectedCompanyName else { return [] }
        return vm.contacts.filter { $0.companyName == name }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular { iPadLayout } else { iPhoneLayout }
            }
            .navigationTitle("Customers")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search customers")
            .task { await vm.load() }
            .navigationDestination(for: CRMContact.self) { CustomerDetailView(contact: $0) }
        }
        .sheet(isPresented: $showNewContact, onDismiss: { Task { await vm.load() } }) {
            NewContactSheet(isPresented: $showNewContact)
        }
    }

    // MARK: - iPad split layout

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            // Left panel
            VStack(spacing: 0) {
                tabPickerBar
                Divider()
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if vm.isLoading && vm.contacts.isEmpty {
                            ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let err = vm.errorMessage {
                            ErrorView(message: err) { Task { await vm.load() } }
                        } else if selectedTab == 0 {
                            iPadPeopleList
                        } else {
                            iPadCompaniesList
                        }
                    }
                    if !showNewContact {
                        FABButton { showNewContact = true }
                            .padding(.trailing, 16).padding(.bottom, 24)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3), value: showNewContact)
            }
            .frame(width: 360)
            .background(Color(.systemGroupedBackground))

            Divider()

            // Right panel
            if selectedTab == 0 {
                if let contact = selectedContact {
                    CustomerDetailPanel(contact: contact) { updated in
                        if let i = vm.contacts.firstIndex(where: { $0.id == updated.id }) {
                            vm.contacts[i] = updated
                        }
                        selectedContact = updated
                    }
                    .id(contact.id)
                } else {
                    rightEmptyState(icon: "person.2", label: "Select a customer to view details")
                }
            } else {
                if let name = selectedCompanyName {
                    CompanyContactsPanel(name: name, contacts: selectedCompanyContacts)
                } else {
                    rightEmptyState(icon: "building.2", label: "Select a company to view details")
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            tabPickerBar
            Divider()
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if vm.isLoading && vm.contacts.isEmpty {
                        ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = vm.errorMessage {
                        ErrorView(message: err) { Task { await vm.load() } }
                    } else if selectedTab == 0 {
                        iPhonePeopleList
                    } else {
                        iPhoneCompaniesList
                    }
                }
                .refreshable { await vm.load() }
                if !showNewContact {
                    FABButton { showNewContact = true }
                        .padding(.trailing, 20).padding(.bottom, 24)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: showNewContact)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Shared header

    private var tabPickerBar: some View {
        Picker("", selection: $selectedTab) {
            Text("People").tag(0)
            Text("Companies (\(companies.count))").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - iPad lists (tap-to-select)

    private var iPadPeopleList: some View {
        Group {
            if vm.filtered.isEmpty {
                EmptyStateView(icon: "person.2", title: "No Customers",
                               message: vm.searchText.isEmpty
                               ? "Add your first customer using the + button."
                               : "No results for \u{201C}\(vm.searchText)\u{201D}")
            } else {
                List {
                    ForEach(vm.filtered) { contact in
                        Button { selectedContact = contact; selectedCompanyName = nil } label: {
                            ContactRow(contact: contact)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedContact?.id == contact.id
                                ? Color(.systemGray5) : Color.clear
                        )
                    }
                    .onDelete { idx in
                        let items = idx.map { vm.filtered[$0] }
                        Task { for c in items { await vm.delete(c) } }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var iPadCompaniesList: some View {
        Group {
            if companies.isEmpty {
                EmptyStateView(icon: "building.2", title: "No Companies",
                               message: "Add a company name to a customer to see companies here.")
            } else {
                List {
                    ForEach(companies, id: \.name) { company in
                        Button { selectedCompanyName = company.name; selectedContact = nil } label: {
                            CompanyRow(name: company.name, contacts: company.contacts)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedCompanyName == company.name
                                ? Color(.systemGray5) : Color.clear
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - iPhone lists (NavigationLink)

    private var iPhonePeopleList: some View {
        Group {
            if vm.filtered.isEmpty {
                EmptyStateView(icon: "person.2", title: "No Customers",
                               message: vm.searchText.isEmpty
                               ? "Add your first customer using the + button."
                               : "No results for \u{201C}\(vm.searchText)\u{201D}")
            } else {
                List {
                    ForEach(vm.filtered) { contact in
                        NavigationLink(value: contact) { ContactRow(contact: contact) }
                    }
                    .onDelete { idx in
                        let items = idx.map { vm.filtered[$0] }
                        Task { for c in items { await vm.delete(c) } }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var iPhoneCompaniesList: some View {
        Group {
            if companies.isEmpty {
                EmptyStateView(icon: "building.2", title: "No Companies",
                               message: "Add a company name to a customer to see companies here.")
            } else {
                List {
                    ForEach(companies, id: \.name) { company in
                        NavigationLink(destination: CompanyDetailView(name: company.name,
                                                                      contacts: company.contacts)) {
                            CompanyRow(name: company.name, contacts: company.contacts)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Empty state

    private func rightEmptyState(icon: String, label: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 52)).foregroundStyle(Color(.systemGray4))
            Text(label).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Customer detail panel (iPad right panel)

struct CustomerDetailPanel: View {
    let contact:   CRMContact
    let onUpdated: (CRMContact) -> Void

    @State private var invoices:         [Invoice] = []
    @State private var isLoadingInvoices = false
    @State private var showEdit          = false
    @State private var previewInvoice:   Invoice?  = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Edit") { showEdit = true }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .background(Color(.secondarySystemGroupedBackground))
            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    avatarSection
                    infoCard
                    invoicesSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
        }
        .task(id: contact.id) { await loadInvoices() }
        .sheet(isPresented: $showEdit) {
            EditContactSheet(contact: contact, isPresented: $showEdit, onSaved: onUpdated)
        }
        .sheet(item: $previewInvoice) { inv in
            InvoicePreviewSheet(invoice: inv, company: nil)
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(avatarColor(contact.displayName).opacity(0.15))
                .frame(width: 72, height: 72)
                .overlay(
                    Text(contact.initials)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(avatarColor(contact.displayName))
                )
            Text(contact.displayName).font(.title3.bold())
            if let company = contact.companyName, !company.isEmpty {
                Text(company).font(.subheadline.bold()).foregroundStyle(.brand)
            }
            if let status = contact.status {
                Text(status.capitalized)
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(statusColor(status).opacity(0.12), in: Capsule())
                    .foregroundStyle(statusColor(status))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            if let email = contact.email {
                ContactInfoRow(icon: "envelope.fill", label: "Email", value: email) {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                }
                if contact.phone != nil { Divider().padding(.leading, 52) }
            }
            if let phone = contact.phone {
                ContactInfoRow(icon: "phone.fill", label: "Phone", value: phone) {
                    let tel = phone.replacingOccurrences(of: " ", with: "")
                    if let url = URL(string: "tel:\(tel)") { UIApplication.shared.open(url) }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var invoicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("INVOICES")
                    .font(.caption.bold()).foregroundStyle(.secondary).tracking(1)
                Spacer()
                if isLoadingInvoices { ProgressView().scaleEffect(0.7) }
            }

            if invoices.isEmpty && !isLoadingInvoices {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text").font(.title2).foregroundStyle(.tertiary)
                    Text("No invoices yet").font(.subheadline).foregroundStyle(.secondary)
                    Text("Invoices sent to this customer will appear here.")
                        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(invoices) { invoice in
                        InvoiceRow(invoice: invoice)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                            .onTapGesture { previewInvoice = invoice }
                        if invoice.id != invoices.last?.id {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func loadInvoices() async {
        isLoadingInvoices = true
        invoices = (try? await APIService.shared.get("/invoices?contactId=\(contact.id)")) ?? []
        isLoadingInvoices = false
    }

    private func avatarColor(_ name: String) -> Color {
        let colors: [Color] = [.brand, .blue, .purple, .green, .pink, .indigo, .teal]
        return colors[abs(name.hashValue) % colors.count]
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "CLIENT":   return .green
        case "LEAD":     return Color(red: 0, green: 0.478, blue: 1)
        case "PROSPECT": return Color(red: 0.686, green: 0.322, blue: 0.871)
        default:         return Color(.systemGray)
        }
    }
}

// MARK: - Company contacts panel (iPad right panel)

struct CompanyContactsPanel: View {
    let name:     String
    let contacts: [CRMContact]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    Text("\(contacts.count) \(contacts.count == 1 ? "contact" : "contacts")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                Spacer()
            }
            .background(Color(.secondarySystemGroupedBackground))
            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Company avatar header
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 72, height: 72)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        Text(name).font(.title3.bold())
                        Text("\(contacts.count) \(contacts.count == 1 ? "person" : "people")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Contacts
                    if !contacts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CONTACTS")
                                .font(.caption.bold()).foregroundStyle(.secondary).tracking(1)
                            VStack(spacing: 0) {
                                ForEach(contacts) { contact in
                                    ContactRow(contact: contact).padding(.horizontal, 16)
                                    if contact.id != contacts.last?.id {
                                        Divider().padding(.leading, 76)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Contact row

struct ContactRow: View {
    let contact: CRMContact

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(avatarColor(contact.displayName).opacity(0.15))
                .frame(width: 46, height: 46)
                .overlay(
                    Text(contact.initials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(avatarColor(contact.displayName))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.displayName)
                    .font(.subheadline.bold()).foregroundStyle(.primary)
                if let company = contact.companyName, !company.isEmpty {
                    Text(company).font(.caption.bold()).foregroundStyle(.brand).lineLimit(1)
                }
                Text(contact.email ?? contact.phone ?? "—")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if let status = contact.status {
                Text(status.capitalized)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor(status).opacity(0.12), in: Capsule())
                    .foregroundStyle(statusColor(status))
            }
        }
        .padding(.vertical, 6)
    }

    private func avatarColor(_ name: String) -> Color {
        let colors: [Color] = [.brand, .blue, .purple, .green, .pink, .indigo, .teal]
        return colors[abs(name.hashValue) % colors.count]
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "CLIENT":   return .green
        case "LEAD":     return Color(red: 0, green: 0.478, blue: 1)
        case "PROSPECT": return Color(red: 0.686, green: 0.322, blue: 0.871)
        default:         return Color(.systemGray)
        }
    }
}

// MARK: - New contact sheet

struct NewContactSheet: View {
    @Binding var isPresented: Bool
    @State private var companyName = ""
    @State private var firstName   = ""
    @State private var lastName    = ""
    @State private var email       = ""
    @State private var phone       = ""
    @State private var saving      = false
    @State private var error       = ""

    private var isValid: Bool {
        !companyName.isEmpty || (!firstName.isEmpty && !lastName.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Company / Organisation", text: $companyName)
                        .textContentType(.organizationName)
                } header: { Text("Company") } footer: {
                    Text("Required if not providing a contact name.").font(.caption)
                }

                Section {
                    TextField("First name", text: $firstName).textContentType(.givenName)
                    TextField("Last name",  text: $lastName).textContentType(.familyName)
                } header: { Text("Contact Name") } footer: {
                    Text("Optional when a company name is provided.").font(.caption)
                }

                Section("Contact details") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone number", text: $phone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                }

                if !error.isEmpty { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle("New Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(!isValid || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        do {
            let co = companyName.trimmingCharacters(in: .whitespaces)
            let fn = firstName.trimmingCharacters(in: .whitespaces)
            let ln = lastName.trimmingCharacters(in: .whitespaces)
            let resolvedFirst: String
            let resolvedLast:  String
            if fn.isEmpty && ln.isEmpty && !co.isEmpty {
                let parts = co.split(separator: " ", maxSplits: 1)
                resolvedFirst = String(parts.first ?? Substring(co))
                resolvedLast  = parts.count > 1 ? String(parts[1]) : co
            } else {
                resolvedFirst = fn; resolvedLast = ln
            }
            let body = CreateContactRequest(
                firstName:   resolvedFirst,
                lastName:    resolvedLast,
                companyName: co.isEmpty ? nil : co,
                email:       email.isEmpty ? nil : email,
                phone:       phone.isEmpty ? nil : phone,
                status:      "LEAD"
            )
            let _: CRMContact = try await APIService.shared.post("/crm/contacts", body: body)
            isPresented = false
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}

// MARK: - Customer detail (iPhone push navigation)

struct CustomerDetailView: View {
    @State private var contact: CRMContact
    @State private var showEdit  = false
    @State private var invoices: [Invoice] = []
    @State private var isLoadingInvoices = false
    @State private var previewInvoice: Invoice? = nil

    init(contact: CRMContact) { _contact = State(initialValue: contact) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Avatar header
                VStack(spacing: 12) {
                    Circle()
                        .fill(avatarColor(contact.displayName).opacity(0.15))
                        .frame(width: 88, height: 88)
                        .overlay(
                            Text(contact.initials)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(avatarColor(contact.displayName))
                        )
                    Text(contact.displayName).font(.title2.bold())
                    if let status = contact.status {
                        Text(status.capitalized)
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(statusColor(status).opacity(0.12), in: Capsule())
                            .foregroundStyle(statusColor(status))
                    }
                }
                .frame(maxWidth: .infinity).padding(.top, 8)

                // Contact info
                VStack(spacing: 0) {
                    if let company = contact.companyName, !company.isEmpty {
                        ContactInfoRow(icon: "building.2.fill", label: "Company", value: company) {}
                        Divider().padding(.leading, 52)
                    }
                    if let email = contact.email {
                        ContactInfoRow(icon: "envelope.fill", label: "Email", value: email) {
                            if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                        }
                        if contact.phone != nil { Divider().padding(.leading, 52) }
                    }
                    if let phone = contact.phone {
                        ContactInfoRow(icon: "phone.fill", label: "Phone", value: phone) {
                            let tel = phone.replacingOccurrences(of: " ", with: "")
                            if let url = URL(string: "tel:\(tel)") { UIApplication.shared.open(url) }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)

                // Invoices
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("INVOICES")
                            .font(.caption.bold()).foregroundStyle(.secondary).tracking(1)
                        Spacer()
                        if isLoadingInvoices { ProgressView().scaleEffect(0.7) }
                    }
                    .padding(.horizontal, 16)

                    if invoices.isEmpty && !isLoadingInvoices {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text").font(.title2).foregroundStyle(.tertiary)
                            Text("No invoices yet").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(invoices) { invoice in
                                InvoiceRow(invoice: invoice)
                                    .padding(.horizontal, 16)
                                    .contentShape(Rectangle())
                                    .onTapGesture { previewInvoice = invoice }
                                if invoice.id != invoices.last?.id {
                                    Divider().padding(.leading, 76)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }.fontWeight(.semibold)
            }
        }
        .task { await loadInvoices() }
        .sheet(isPresented: $showEdit) {
            EditContactSheet(contact: contact, isPresented: $showEdit) { updated in contact = updated }
        }
        .sheet(item: $previewInvoice) { inv in
            InvoicePreviewSheet(invoice: inv, company: nil)
        }
    }

    private func loadInvoices() async {
        isLoadingInvoices = true
        invoices = (try? await APIService.shared.get("/invoices?contactId=\(contact.id)")) ?? []
        isLoadingInvoices = false
    }

    private func avatarColor(_ name: String) -> Color {
        let colors: [Color] = [.brand, .blue, .purple, .green, .pink, .indigo, .teal]
        return colors[abs(name.hashValue) % colors.count]
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "CLIENT":   return .green
        case "LEAD":     return Color(red: 0, green: 0.478, blue: 1)
        case "PROSPECT": return Color(red: 0.686, green: 0.322, blue: 0.871)
        default:         return Color(.systemGray)
        }
    }

    private func shortDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withFullDate]
        guard let d = fmt.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateStyle = .medium
        return out.string(from: d)
    }
}

// MARK: - Contact info row (shared)

struct ContactInfoRow: View {
    let icon:   String
    let label:  String
    let value:  String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.brand)
                    .frame(width: 36, height: 36)
                    .background(Color.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.subheadline).foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit contact sheet

struct EditContactSheet: View {
    let contact:      CRMContact
    @Binding var isPresented: Bool
    let onSaved:      (CRMContact) -> Void

    @State private var firstName:   String
    @State private var lastName:    String
    @State private var companyName: String
    @State private var email:       String
    @State private var phone:       String
    @State private var status:      String
    @State private var saving       = false
    @State private var error        = ""

    private let statuses = ["LEAD", "PROSPECT", "CLIENT"]

    init(contact: CRMContact, isPresented: Binding<Bool>, onSaved: @escaping (CRMContact) -> Void) {
        self.contact      = contact
        self._isPresented = isPresented
        self.onSaved      = onSaved
        _firstName   = State(initialValue: contact.firstName)
        _lastName    = State(initialValue: contact.lastName)
        _companyName = State(initialValue: contact.companyName ?? "")
        _email       = State(initialValue: contact.email ?? "")
        _phone       = State(initialValue: contact.phone ?? "")
        _status      = State(initialValue: contact.status ?? "LEAD")
    }

    private var isValid: Bool { !firstName.isEmpty && !lastName.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First name", text: $firstName).textContentType(.givenName)
                    TextField("Last name",  text: $lastName).textContentType(.familyName)
                }
                Section("Company") {
                    TextField("Company / Organisation (optional)", text: $companyName)
                        .textContentType(.organizationName)
                }
                Section("Contact details") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone number", text: $phone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                }
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { s in Text(s.capitalized).tag(s) }
                    }
                    .pickerStyle(.segmented)
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle("Edit Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(!isValid || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        do {
            let body = UpdateContactRequest(
                firstName:   firstName.trimmingCharacters(in: .whitespaces),
                lastName:    lastName.trimmingCharacters(in: .whitespaces),
                companyName: companyName.isEmpty ? nil : companyName.trimmingCharacters(in: .whitespaces),
                email:       email.isEmpty ? nil : email,
                phone:       phone.isEmpty ? nil : phone,
                status:      status
            )
            let updated: CRMContact = try await APIService.shared.put("/crm/contacts/\(contact.id)", body: body)
            onSaved(updated)
            isPresented = false
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}

// MARK: - Company row

struct CompanyRow: View {
    let name:     String
    let contacts: [CRMContact]

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.12)).frame(width: 46, height: 46)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.bold()).foregroundStyle(.primary)
                Text("\(contacts.count) \(contacts.count == 1 ? "person" : "people")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Company detail view (iPhone push navigation)

struct CompanyDetailView: View {
    let name:     String
    let contacts: [CRMContact]

    var body: some View {
        List {
            ForEach(contacts) { contact in
                NavigationLink(value: contact) { ContactRow(contact: contact) }
            }
        }
        .listStyle(.plain)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CRMContact.self) { CustomerDetailView(contact: $0) }
    }
}
