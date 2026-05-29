import SwiftUI
import UniformTypeIdentifiers

// MARK: - View model

@MainActor
final class SuppliersViewModel: ObservableObject {
    @Published var suppliers:    [Supplier] = []
    @Published var isLoading     = false
    @Published var errorMessage: String?
    @Published var searchText    = ""

    var filtered: [Supplier] {
        guard !searchText.isEmpty else { return suppliers }
        let q = searchText.lowercased()
        return suppliers.filter {
            $0.name.lowercased().contains(q)
            || ($0.contactPerson?.lowercased().contains(q) == true)
            || ($0.email?.lowercased().contains(q) == true)
            || ($0.phone?.contains(q) == true)
        }
    }

    func load() async {
        isLoading    = true
        errorMessage = nil
        do {
            suppliers = try await APIService.shared.get("/vendors")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ supplier: Supplier) async {
        try? await APIService.shared.delete("/vendors/\(supplier.id)")
        suppliers.removeAll { $0.id == supplier.id }
    }
}

// MARK: - Main view

struct SuppliersView: View {
    @StateObject private var vm = SuppliersViewModel()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showNewSupplier  = false
    @State private var selectedTab      = 0   // 0 = Companies, 1 = Contacts
    @State private var selectedSupplier: Supplier? = nil

    private var withContacts: [Supplier] {
        vm.filtered.filter { $0.contactPerson?.isEmpty == false && $0.contactPerson != nil }
    }

    var body: some View {
        if sizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: iPad layout

    private var iPadLayout: some View {
        NavigationStack {
            HStack(spacing: 0) {
                leftPanel
                    .frame(width: 360)
                Divider()
                rightPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Suppliers")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load() }
        }
        .sheet(isPresented: $showNewSupplier, onDismiss: { Task { await vm.load() } }) {
            NewSupplierSheet(isPresented: $showNewSupplier) { created in
                selectedSupplier = created
            }
        }
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Companies (\(vm.filtered.count))").tag(0)
                Text("Contacts (\(withContacts.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            Divider()

            ZStack(alignment: .bottomTrailing) {
                Group {
                    if vm.isLoading && vm.suppliers.isEmpty {
                        ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = vm.errorMessage {
                        ErrorView(message: err) { Task { await vm.load() } }
                    } else if selectedTab == 0 {
                        iPadCompaniesList
                    } else {
                        iPadContactsList
                    }
                }
                .refreshable { await vm.load() }

                if !showNewSupplier {
                    FABButton { showNewSupplier = true }
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $vm.searchText, prompt: "Search suppliers")
    }

    @ViewBuilder
    private var rightPanel: some View {
        if let supplier = selectedSupplier {
            SupplierDetailPanel(
                supplier: supplier,
                onUpdated: { updated in
                    selectedSupplier = updated
                    if let idx = vm.suppliers.firstIndex(where: { $0.id == updated.id }) {
                        vm.suppliers[idx] = updated
                    }
                }
            )
            .id(supplier.id)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(.systemGray4))
                Text("Select a supplier")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                Text("Tap a supplier from the list to view details and expenses.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var iPadCompaniesList: some View {
        Group {
            if vm.filtered.isEmpty {
                EmptyStateView(
                    icon:    "shippingbox",
                    title:   "No Suppliers",
                    message: vm.searchText.isEmpty
                        ? "Add your first supplier using the + button."
                        : "No results for \u{201C}\(vm.searchText)\u{201D}"
                )
            } else {
                List {
                    ForEach(vm.filtered) { supplier in
                        Button { selectedSupplier = supplier } label: {
                            SupplierRow(supplier: supplier)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedSupplier?.id == supplier.id
                                ? Color(.systemGray5)
                                : Color(.secondarySystemGroupedBackground)
                        )
                    }
                    .onDelete { idx in
                        let items = idx.map { vm.filtered[$0] }
                        Task { for s in items { await vm.delete(s) } }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var iPadContactsList: some View {
        Group {
            if withContacts.isEmpty {
                EmptyStateView(
                    icon:    "person.text.rectangle",
                    title:   "No Contacts",
                    message: "Add a contact person when creating or editing a supplier."
                )
            } else {
                List {
                    ForEach(withContacts) { supplier in
                        Button { selectedSupplier = supplier } label: {
                            SupplierContactRow(supplier: supplier)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedSupplier?.id == supplier.id
                                ? Color(.systemGray5)
                                : Color(.secondarySystemGroupedBackground)
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Companies (\(vm.filtered.count))").tag(0)
                    Text("Contacts (\(withContacts.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGroupedBackground))

                Divider()

                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if vm.isLoading && vm.suppliers.isEmpty {
                            ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let err = vm.errorMessage {
                            ErrorView(message: err) { Task { await vm.load() } }
                        } else if selectedTab == 0 {
                            companiesList
                        } else {
                            contactsList
                        }
                    }
                    .refreshable { await vm.load() }

                    if !showNewSupplier {
                        FABButton { showNewSupplier = true }
                            .padding(.trailing, 20)
                            .padding(.bottom, 24)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3), value: showNewSupplier)
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $vm.searchText, prompt: "Search suppliers")
            .navigationTitle("Suppliers")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Supplier.self) { SupplierDetailView(supplier: $0) }
            .task { await vm.load() }
        }
        .sheet(isPresented: $showNewSupplier, onDismiss: { Task { await vm.load() } }) {
            NewSupplierSheet(isPresented: $showNewSupplier)
        }
    }

    // MARK: iPhone lists (NavigationLink)

    private var companiesList: some View {
        Group {
            if vm.filtered.isEmpty {
                EmptyStateView(
                    icon:    "shippingbox",
                    title:   "No Suppliers",
                    message: vm.searchText.isEmpty
                        ? "Add your first supplier using the + button."
                        : "No results for \u{201C}\(vm.searchText)\u{201D}"
                )
            } else {
                List {
                    ForEach(vm.filtered) { supplier in
                        NavigationLink(value: supplier) { SupplierRow(supplier: supplier) }
                    }
                    .onDelete { idx in
                        let items = idx.map { vm.filtered[$0] }
                        Task { for s in items { await vm.delete(s) } }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var contactsList: some View {
        Group {
            if withContacts.isEmpty {
                EmptyStateView(
                    icon:    "person.text.rectangle",
                    title:   "No Contacts",
                    message: "Add a contact person when creating or editing a supplier."
                )
            } else {
                List {
                    ForEach(withContacts) { supplier in
                        NavigationLink(value: supplier) {
                            SupplierContactRow(supplier: supplier)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Supplier detail panel (iPad right panel)

struct SupplierDetailPanel: View {
    let onUpdated: (Supplier) -> Void

    @State private var supplier:         Supplier
    @State private var showEdit          = false
    @State private var showScanCamera    = false
    @State private var showUploadPicker  = false
    @State private var showFABMenu       = false
    @State private var expenses:         [SupplierExpense] = []
    @State private var isLoadingExpenses = false

    @State private var isParsing       = false
    @State private var parseError:     String?
    @State private var showParseError  = false
    @State private var parsedQuote:    ParsedQuote?
    @State private var uploadedDocId:  String?
    @State private var showNewExpense  = false

    init(supplier: Supplier, onUpdated: @escaping (Supplier) -> Void) {
        _supplier  = State(initialValue: supplier)
        self.onUpdated = onUpdated
    }

    var body: some View {
        VStack(spacing: 0) {
            panelToolbar
            Divider()
            ScrollView {
                VStack(spacing: 24) {
                    supplierHeader
                    infoCard
                    expensesSection
                }
                .padding(.bottom, 96)
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottomTrailing) {
            FABButton { showFABMenu = true }
                .padding(.trailing, 20)
                .padding(.bottom, 32)
        }
        .overlay {
            if isParsing {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.4).tint(.white)
                        Text("Reading document…")
                            .font(.subheadline.bold()).foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .task(id: supplier.id) { await loadExpenses() }
        .confirmationDialog("Add from Supplier", isPresented: $showFABMenu, titleVisibility: .visible) {
            Button("Scan Receipt / Invoice")   { showScanCamera = true }
            Button("Upload Receipt / Invoice") { showUploadPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showScanCamera) {
            DocumentCameraView(
                onScan: { images in
                    showScanCamera = false
                    Task { await parseScanned(images) }
                },
                onCancel: { showScanCamera = false }
            )
        }
        .fileImporter(
            isPresented: $showUploadPicker,
            allowedContentTypes: [.pdf, .jpeg, .png, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await handleUpload(url: url) }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditSupplierSheet(supplier: supplier, isPresented: $showEdit) { updated in
                supplier = updated
                onUpdated(updated)
            }
        }
        .sheet(isPresented: $showNewExpense, onDismiss: { Task { await loadExpenses() } }) {
            NewExpenseFromSupplierSheet(
                presetSupplier: supplier,
                parsed:         parsedQuote,
                docId:          uploadedDocId,
                isPresented:    $showNewExpense
            )
        }
        .alert("Could not read document", isPresented: $showParseError) {
            Button("Try again")  { showNewExpense = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(parseError ?? "The document could not be parsed. You can still enter details manually.")
        }
    }

    // MARK: Subviews

    private var panelToolbar: some View {
        HStack {
            Text(supplier.name)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button("Edit") { showEdit = true }
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var supplierHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(avatarColor(supplier.name).opacity(0.13))
                    .frame(width: 72, height: 72)
                Text(supplier.initials)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(avatarColor(supplier.name))
            }
            Text(supplier.name)
                .font(.title2.bold())
            if let cp = supplier.contactPerson, !cp.isEmpty {
                Label(cp, systemImage: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            if let email = supplier.email {
                ContactInfoRow(icon: "envelope.fill", label: "Email", value: email) {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                }
                if supplier.phone != nil || supplier.website != nil || supplier.taxNumber != nil {
                    Divider().padding(.leading, 52)
                }
            }
            if let phone = supplier.phone {
                ContactInfoRow(icon: "phone.fill", label: "Phone", value: phone) {
                    let tel = phone.replacingOccurrences(of: " ", with: "")
                    if let url = URL(string: "tel:\(tel)") { UIApplication.shared.open(url) }
                }
                if supplier.website != nil || supplier.taxNumber != nil {
                    Divider().padding(.leading, 52)
                }
            }
            if let web = supplier.website, !web.isEmpty {
                ContactInfoRow(icon: "globe", label: "Website", value: web) {
                    let urlStr = web.hasPrefix("http") ? web : "https://\(web)"
                    if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
                }
                if supplier.taxNumber != nil { Divider().padding(.leading, 52) }
            }
            if let tax = supplier.taxNumber, !tax.isEmpty {
                ContactInfoRow(icon: "number", label: "Tax / VAT", value: tax) {}
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private var expensesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXPENSES")
                    .font(.caption.bold()).foregroundStyle(.secondary).tracking(1)
                Spacer()
                if isLoadingExpenses { ProgressView().scaleEffect(0.7) }
            }
            .padding(.horizontal, 16)

            if expenses.isEmpty && !isLoadingExpenses {
                VStack(spacing: 10) {
                    Image(systemName: "creditcard").font(.title2).foregroundStyle(.tertiary)
                    Text("No expenses yet").font(.subheadline).foregroundStyle(.secondary)
                    Text("Tap + to scan or upload a receipt/invoice.")
                        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(expenses.indices, id: \.self) { i in
                        SupplierExpenseRow(expense: expenses[i])
                        if i < expenses.count - 1 { Divider().padding(.leading, 52) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Actions

    private func loadExpenses() async {
        isLoadingExpenses = true
        expenses = (try? await APIService.shared.get("/expenses?vendorId=\(supplier.id)")) ?? []
        isLoadingExpenses = false
    }

    private func parseScanned(_ images: [UIImage]) async {
        isParsing = true
        do {
            let parsed = try await DocumentService.shared.parseVendorQuote(images: images)
            let doc    = try? await DocumentService.shared.uploadScan(images: images, type: .receipt)
            parsedQuote = parsed; uploadedDocId = doc?.id
            isParsing = false; showNewExpense = true
        } catch {
            isParsing = false; parsedQuote = nil; uploadedDocId = nil
            parseError = error.localizedDescription; showParseError = true
        }
    }

    private func handleUpload(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        isParsing = true
        do {
            let data     = try Data(contentsOf: url)
            let mimeType = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"
            let parsed   = try await DocumentService.shared.parseVendorQuoteFromData(data, mimeType: mimeType)
            let doc      = try? await DocumentService.shared.uploadFile(
                data: data, fileName: url.lastPathComponent, mimeType: mimeType, type: .receipt)
            parsedQuote = parsed; uploadedDocId = doc?.id
            isParsing = false; showNewExpense = true
        } catch {
            isParsing = false; parsedQuote = nil; uploadedDocId = nil
            parseError = error.localizedDescription; showParseError = true
        }
    }

    private func avatarColor(_ name: String) -> Color {
        let colors: [Color] = [.green, .teal, .blue, .indigo, .orange, .purple, .pink]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Supplier row (company-centric)

struct SupplierRow: View {
    let supplier: Supplier

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(avatarColor(supplier.name).opacity(0.13))
                    .frame(width: 46, height: 46)
                Text(supplier.initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(avatarColor(supplier.name))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(supplier.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                if let cp = supplier.contactPerson, !cp.isEmpty {
                    Label(cp, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let phone = supplier.phone ?? supplier.email {
                    Text(phone)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func avatarColor(_ name: String) -> Color {
        let colors: [Color] = [.green, .teal, .blue, .indigo, .orange, .purple, .pink]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Contact row (person-centric, shown in Contacts tab)

private struct SupplierContactRow: View {
    let supplier: Supplier

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.green.opacity(0.13))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(supplier.contactPerson ?? "")
                    .font(.subheadline.bold())
                Text(supplier.name)
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .lineLimit(1)
                if let contact = supplier.email ?? supplier.phone {
                    Text(contact).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - New supplier sheet

struct NewSupplierSheet: View {
    @Binding var isPresented: Bool
    var onCreated: ((Supplier) -> Void)? = nil

    @State private var name          = ""
    @State private var contactPerson = ""
    @State private var email         = ""
    @State private var phone         = ""
    @State private var website       = ""
    @State private var taxNumber     = ""
    @State private var notes         = ""
    @State private var saving        = false
    @State private var error         = ""

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Makro, Google, Municipality", text: $name)
                        .textContentType(.organizationName)
                } header: {
                    Text("Supplier / Company Name")
                } footer: {
                    Text("Required — the main name used to identify this supplier.")
                        .font(.caption)
                }

                Section("Contact Person") {
                    TextField("Full name (optional)", text: $contactPerson)
                        .textContentType(.name)
                }

                Section("Contact Details") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone number", text: $phone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    TextField("Website (optional)", text: $website)
                        .textContentType(.URL).keyboardType(.URL).autocapitalization(.none)
                }

                Section("Financial") {
                    TextField("Tax / VAT number (optional)", text: $taxNumber)
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(3)
                }

                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("New Supplier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().scaleEffect(0.8) }
                        else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(!isValid || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        do {
            let body = CreateSupplierRequest(
                name:          name.trimmingCharacters(in: .whitespaces),
                contactPerson: contactPerson.isEmpty ? nil : contactPerson.trimmingCharacters(in: .whitespaces),
                email:         email.isEmpty ? nil : email,
                phone:         phone.isEmpty ? nil : phone,
                website:       website.isEmpty ? nil : website,
                taxNumber:     taxNumber.isEmpty ? nil : taxNumber,
                notes:         notes.isEmpty ? nil : notes
            )
            let created: Supplier = try await APIService.shared.post("/vendors", body: body)
            onCreated?(created)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}

// MARK: - Edit supplier sheet

struct EditSupplierSheet: View {
    let supplier:     Supplier
    @Binding var isPresented: Bool
    let onSaved:      (Supplier) -> Void

    @State private var name:          String
    @State private var contactPerson: String
    @State private var email:         String
    @State private var phone:         String
    @State private var website:       String
    @State private var taxNumber:     String
    @State private var notes:         String
    @State private var saving         = false
    @State private var error          = ""

    init(supplier: Supplier, isPresented: Binding<Bool>, onSaved: @escaping (Supplier) -> Void) {
        self.supplier     = supplier
        self._isPresented = isPresented
        self.onSaved      = onSaved
        _name          = State(initialValue: supplier.name)
        _contactPerson = State(initialValue: supplier.contactPerson ?? "")
        _email         = State(initialValue: supplier.email ?? "")
        _phone         = State(initialValue: supplier.phone ?? "")
        _website       = State(initialValue: supplier.website ?? "")
        _taxNumber     = State(initialValue: supplier.taxNumber ?? "")
        _notes         = State(initialValue: supplier.notes ?? "")
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplier / Company Name") {
                    TextField("Company name", text: $name)
                        .textContentType(.organizationName)
                }

                Section("Contact Person") {
                    TextField("Full name (optional)", text: $contactPerson)
                        .textContentType(.name)
                }

                Section("Contact Details") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone number", text: $phone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    TextField("Website (optional)", text: $website)
                        .textContentType(.URL).keyboardType(.URL).autocapitalization(.none)
                }

                Section("Financial") {
                    TextField("Tax / VAT number (optional)", text: $taxNumber)
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(3)
                }

                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Edit Supplier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().scaleEffect(0.8) }
                        else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(!isValid || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        do {
            let body = UpdateSupplierRequest(
                name:          name.trimmingCharacters(in: .whitespaces),
                contactPerson: contactPerson.isEmpty ? nil : contactPerson.trimmingCharacters(in: .whitespaces),
                email:         email.isEmpty ? nil : email,
                phone:         phone.isEmpty ? nil : phone,
                website:       website.isEmpty ? nil : website,
                taxNumber:     taxNumber.isEmpty ? nil : taxNumber,
                notes:         notes.isEmpty ? nil : notes
            )
            let updated: Supplier = try await APIService.shared.put("/vendors/\(supplier.id)", body: body)
            onSaved(updated)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}

// MARK: - Supplier detail view (iPhone)

struct SupplierDetailView: View {
    @State private var supplier:         Supplier
    @State private var showEdit          = false
    @State private var showScanCamera    = false
    @State private var showUploadPicker  = false
    @State private var showFABMenu       = false
    @State private var expenses:         [SupplierExpense] = []
    @State private var isLoadingExpenses = false

    @State private var isParsing       = false
    @State private var parseError:     String?
    @State private var showParseError  = false
    @State private var parsedQuote:    ParsedQuote?
    @State private var uploadedDocId:  String?
    @State private var showNewExpense  = false

    init(supplier: Supplier) {
        _supplier = State(initialValue: supplier)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                supplierHeader
                infoCard
                expensesSection
            }
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(supplier.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            FABButton { showFABMenu = true }
                .padding(.trailing, 20)
                .padding(.bottom, 32)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }.fontWeight(.semibold)
            }
        }
        .task { await loadExpenses() }
        .confirmationDialog("Add from Supplier", isPresented: $showFABMenu, titleVisibility: .visible) {
            Button("Scan Receipt / Invoice")   { showScanCamera = true }
            Button("Upload Receipt / Invoice") { showUploadPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showScanCamera) {
            DocumentCameraView(
                onScan: { images in
                    showScanCamera = false
                    Task { await parseScanned(images) }
                },
                onCancel: { showScanCamera = false }
            )
        }
        .fileImporter(
            isPresented: $showUploadPicker,
            allowedContentTypes: [.pdf, .jpeg, .png, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await handleUpload(url: url) }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditSupplierSheet(supplier: supplier, isPresented: $showEdit) { updated in
                supplier = updated
            }
        }
        .sheet(isPresented: $showNewExpense, onDismiss: { Task { await loadExpenses() } }) {
            NewExpenseFromSupplierSheet(
                presetSupplier: supplier,
                parsed:         parsedQuote,
                docId:          uploadedDocId,
                isPresented:    $showNewExpense
            )
        }
        .overlay {
            if isParsing {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.4).tint(.white)
                        Text("Reading document…")
                            .font(.subheadline.bold()).foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .alert("Could not read document", isPresented: $showParseError) {
            Button("Try again")  { showNewExpense = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(parseError ?? "The document could not be parsed. You can still enter details manually.")
        }
    }

    // MARK: Subviews

    private var supplierHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(avatarColor(supplier.name).opacity(0.13))
                    .frame(width: 88, height: 88)
                Text(supplier.initials)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(avatarColor(supplier.name))
            }
            Text(supplier.name)
                .font(.title2.bold())
            if let cp = supplier.contactPerson, !cp.isEmpty {
                Label(cp, systemImage: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            if let email = supplier.email {
                ContactInfoRow(icon: "envelope.fill", label: "Email", value: email) {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                }
                if supplier.phone != nil || supplier.website != nil || supplier.taxNumber != nil {
                    Divider().padding(.leading, 52)
                }
            }
            if let phone = supplier.phone {
                ContactInfoRow(icon: "phone.fill", label: "Phone", value: phone) {
                    let tel = phone.replacingOccurrences(of: " ", with: "")
                    if let url = URL(string: "tel:\(tel)") { UIApplication.shared.open(url) }
                }
                if supplier.website != nil || supplier.taxNumber != nil {
                    Divider().padding(.leading, 52)
                }
            }
            if let web = supplier.website, !web.isEmpty {
                ContactInfoRow(icon: "globe", label: "Website", value: web) {
                    let urlStr = web.hasPrefix("http") ? web : "https://\(web)"
                    if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
                }
                if supplier.taxNumber != nil { Divider().padding(.leading, 52) }
            }
            if let tax = supplier.taxNumber, !tax.isEmpty {
                ContactInfoRow(icon: "number", label: "Tax / VAT", value: tax) {}
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private var expensesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXPENSES")
                    .font(.caption.bold()).foregroundStyle(.secondary).tracking(1)
                Spacer()
                if isLoadingExpenses { ProgressView().scaleEffect(0.7) }
            }
            .padding(.horizontal, 16)

            if expenses.isEmpty && !isLoadingExpenses {
                VStack(spacing: 10) {
                    Image(systemName: "creditcard").font(.title2).foregroundStyle(.tertiary)
                    Text("No expenses yet").font(.subheadline).foregroundStyle(.secondary)
                    Text("Tap + to scan or upload a receipt/invoice.")
                        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(expenses.indices, id: \.self) { i in
                        SupplierExpenseRow(expense: expenses[i])
                        if i < expenses.count - 1 { Divider().padding(.leading, 52) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Actions

    private func loadExpenses() async {
        isLoadingExpenses = true
        expenses = (try? await APIService.shared.get("/expenses?vendorId=\(supplier.id)")) ?? []
        isLoadingExpenses = false
    }

    private func parseScanned(_ images: [UIImage]) async {
        isParsing = true
        do {
            let parsed = try await DocumentService.shared.parseVendorQuote(images: images)
            let doc    = try? await DocumentService.shared.uploadScan(images: images, type: .receipt)
            parsedQuote = parsed; uploadedDocId = doc?.id
            isParsing = false; showNewExpense = true
        } catch {
            isParsing = false; parsedQuote = nil; uploadedDocId = nil
            parseError = error.localizedDescription; showParseError = true
        }
    }

    private func handleUpload(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        isParsing = true
        do {
            let data     = try Data(contentsOf: url)
            let mimeType = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"
            let parsed   = try await DocumentService.shared.parseVendorQuoteFromData(data, mimeType: mimeType)
            let doc      = try? await DocumentService.shared.uploadFile(
                data: data, fileName: url.lastPathComponent, mimeType: mimeType, type: .receipt)
            parsedQuote = parsed; uploadedDocId = doc?.id
            isParsing = false; showNewExpense = true
        } catch {
            isParsing = false; parsedQuote = nil; uploadedDocId = nil
            parseError = error.localizedDescription; showParseError = true
        }
    }

    private func avatarColor(_ name: String) -> Color {
        let colors: [Color] = [.green, .teal, .blue, .indigo, .orange, .purple, .pink]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Supplier expense model (local, detail view only)

private struct SupplierExpense: Decodable, Identifiable {
    let id:          String
    var total:       Double
    var description: String?
    var status:      String?
    let date:        String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try  c.decode(String.self,  forKey: .id)
        total       = (try? c.decode(Double.self, forKey: .total)) ?? 0
        description = try? c.decode(String.self,  forKey: .description)
        status      = try? c.decode(String.self,  forKey: .status)
        date        = try? c.decode(String.self,  forKey: .date)
    }

    private enum CodingKeys: String, CodingKey { case id, total, description, status, date }
}

private struct SupplierExpenseRow: View {
    let expense: SupplierExpense

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 14)).foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.description ?? "Expense").font(.subheadline.bold()).lineLimit(1)
                if let d = expense.date { Text(shortDate(d)).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(expense.total, format: .currency(code: "ZAR").presentation(.narrow))
                    .font(.subheadline.bold())
                if let s = expense.status {
                    Text(s.capitalized).font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(statusColor(s).opacity(0.12), in: Capsule())
                        .foregroundStyle(statusColor(s))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withFullDate]
        guard let d = f.date(from: iso) ?? f2.date(from: iso) else { return iso }
        return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
    }
    private func statusColor(_ s: String) -> Color {
        switch s { case "PAID": return .green; case "OVERDUE": return .red; default: return .orange }
    }
}

// MARK: - New expense sheet (supplier optional — used from detail view and purchases)

struct NewExpenseFromSupplierSheet: View {
    let presetSupplier:   Supplier?
    let parsed:           ParsedQuote?
    let docId:            String?
    @Binding var isPresented: Bool

    @State private var selectedSupplier: Supplier?
    @State private var showSupplierPicker = false

    @State private var description = ""
    @State private var totalStr    = ""
    @State private var dateOn      = true
    @State private var expenseDate = Date()
    @State private var notes       = ""
    @State private var status      = "UNPAID"
    @State private var saving      = false
    @State private var error       = ""

    private let statuses = ["UNPAID", "PAID", "OVERDUE"]

    init(presetSupplier: Supplier?, parsed: ParsedQuote?, docId: String?, isPresented: Binding<Bool>) {
        self.presetSupplier = presetSupplier
        self.parsed         = parsed
        self.docId          = docId
        self._isPresented   = isPresented
        _selectedSupplier   = State(initialValue: presetSupplier)

        let desc   = parsed?.projectName ?? parsed?.vendorName ?? parsed?.notes ?? ""
        let amount = parsed?.subtotal ?? parsed?.total ?? 0
        _description = State(initialValue: desc)
        _totalStr    = State(initialValue: amount > 0 ? String(format: "%.2f", amount) : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplier") {
                    if let s = selectedSupplier {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.green.opacity(0.13))
                                    .frame(width: 36, height: 36)
                                Text(s.initials).font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.subheadline.bold())
                                if let cp = s.contactPerson, !cp.isEmpty {
                                    Text(cp).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if presetSupplier == nil {
                                Button("Change") { showSupplierPicker = true }
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                    } else {
                        Button { showSupplierPicker = true } label: {
                            HStack {
                                Image(systemName: "shippingbox.fill").foregroundStyle(.green).frame(width: 28)
                                Text("Assign Supplier")
                                    .foregroundStyle(parsed?.vendorName != nil ? .primary : .secondary)
                                if let vn = parsed?.vendorName {
                                    Text("· \(vn)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let items = parsed?.lineItems, items.count > 1 {
                    Section("Extracted Line Items") {
                        ForEach(items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.description).font(.subheadline).lineLimit(2)
                                    Text("Qty \(item.quantity, specifier: "%.0f") × \(item.unitPrice, specifier: "%.2f")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.total, format: .currency(code: "ZAR").presentation(.narrow))
                                    .font(.subheadline.bold())
                            }
                        }
                    }
                }

                Section("Expense Details") {
                    TextField("Description", text: $description, axis: .vertical).lineLimit(2)
                    HStack {
                        Text("Amount (ZAR)")
                        Spacer()
                        TextField("0.00", text: $totalStr)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                    }
                }

                Section("Date") {
                    Toggle("Set date", isOn: $dateOn.animation())
                    if dateOn { DatePicker("Date", selection: $expenseDate, displayedComponents: .date) }
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(3)
                }

                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(saving || totalStr.isEmpty)
                }
            }
            .sheet(isPresented: $showSupplierPicker) {
                SupplierPickerSheet(selected: $selectedSupplier, suggestedName: parsed?.vendorName)
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        do {
            let dateStr: String? = dateOn
                ? { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f.string(from: expenseDate) }()
                : nil
            let body = CreateExpenseRequest(
                vendorId:    selectedSupplier?.id,
                description: description.isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
                amount:      Double(totalStr) ?? 0,
                tax:         nil,
                date:        dateStr,
                notes:       notes.isEmpty ? nil : notes,
                reference:   nil
            )
            let _: SupplierExpenseCreated = try await APIService.shared.post("/expenses", body: body)
            isPresented = false
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}

private struct SupplierExpenseCreated: Decodable { let id: String? }

// MARK: - Supplier picker sheet

struct SupplierPickerSheet: View {
    @Binding var selected:  Supplier?
    let suggestedName:      String?
    @Environment(\.dismiss) private var dismiss

    @State private var suppliers:    [Supplier] = []
    @State private var isLoading     = false
    @State private var searchText    = ""
    @State private var showCreate    = false
    @State private var createPrefill = ""

    private var filtered: [Supplier] {
        guard !searchText.isEmpty else { return suppliers }
        let q = searchText.lowercased()
        return suppliers.filter {
            $0.name.lowercased().contains(q)
            || ($0.contactPerson?.lowercased().contains(q) == true)
        }
    }

    private var suggestedAlreadyExists: Bool {
        guard let n = suggestedName?.lowercased(), !n.isEmpty else { return true }
        return suppliers.contains { $0.name.lowercased().contains(n) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let n = suggestedName, !n.isEmpty, !suggestedAlreadyExists {
                    Section {
                        Button {
                            createPrefill = n; showCreate = true
                        } label: {
                            Label("Create \"\(n)\" as new supplier", systemImage: "plus.circle.fill")
                                .foregroundStyle(.green).font(.subheadline.bold())
                        }
                    }
                }

                if isLoading {
                    Section { HStack { Spacer(); ProgressView(); Spacer() } }
                } else if filtered.isEmpty {
                    Section {
                        Text("No suppliers found.").foregroundStyle(.secondary).font(.subheadline)
                    }
                } else {
                    Section("Existing Suppliers") {
                        ForEach(filtered) { supplier in
                            Button {
                                selected = supplier; dismiss()
                            } label: {
                                HStack {
                                    SupplierRow(supplier: supplier)
                                    if selected?.id == supplier.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search suppliers")
            .navigationTitle("Assign Supplier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { selected = nil; dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { createPrefill = ""; showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(isPresented: $showCreate) {
                QuickCreateSupplierView(prefillName: createPrefill) { created in
                    selected = created; dismiss()
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        suppliers = (try? await APIService.shared.get("/vendors")) ?? []
        isLoading = false
    }
}

// MARK: - Quick-create supplier (navigation destination inside picker)

private struct QuickCreateSupplierView: View {
    let prefillName: String
    let onCreated:   (Supplier) -> Void

    @State private var name          = ""
    @State private var contactPerson = ""
    @State private var email         = ""
    @State private var phone         = ""
    @State private var saving        = false
    @State private var error         = ""

    init(prefillName: String, onCreated: @escaping (Supplier) -> Void) {
        self.prefillName = prefillName
        self.onCreated   = onCreated
        _name = State(initialValue: prefillName)
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section {
                TextField("Company / supplier name", text: $name)
                    .textContentType(.organizationName)
            } header: { Text("Supplier Name") }

            Section("Contact Person") {
                TextField("Full name (optional)", text: $contactPerson).textContentType(.name)
            }
            Section("Contact Details") {
                TextField("Email address", text: $email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress).autocapitalization(.none)
                TextField("Phone number", text: $phone)
                    .textContentType(.telephoneNumber).keyboardType(.phonePad)
            }
            if !error.isEmpty {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("New Supplier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await save() } } label: {
                    if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                }
                .disabled(!isValid || saving)
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        do {
            let body = CreateSupplierRequest(
                name:          name.trimmingCharacters(in: .whitespaces),
                contactPerson: contactPerson.isEmpty ? nil : contactPerson.trimmingCharacters(in: .whitespaces),
                email:         email.isEmpty ? nil : email,
                phone:         phone.isEmpty ? nil : phone,
                website:       nil,
                taxNumber:     nil,
                notes:         nil
            )
            let created: Supplier = try await APIService.shared.post("/vendors", body: body)
            onCreated(created)
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}
