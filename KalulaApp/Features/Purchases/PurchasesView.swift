import SwiftUI
import UniformTypeIdentifiers

// MARK: - Local models

private struct BillDoc: Decodable, Identifiable {
    let id: String
    let fileName: String?
}

private struct PurchaseBill: Decodable, Identifiable {
    let id:         String
    let number:     String?
    var status:     String?
    var dueDate:    String?
    var total:      Double
    var paidAmount: Double?
    let vendor:     VendorRef?
    var notes:      String?
    let documents:  [BillDoc]?

    struct VendorRef: Decodable { let name: String? }

    var remaining: Double { total - (paidAmount ?? 0) }

    private enum CodingKeys: String, CodingKey {
        case id, number, status, dueDate, total, paidAmount, vendor, notes, documents
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try  c.decode(String.self,      forKey: .id)
        number     = try? c.decode(String.self,      forKey: .number)
        status     = try? c.decode(String.self,      forKey: .status)
        dueDate    = try? c.decode(String.self,      forKey: .dueDate)
        total      = (try? c.decode(Double.self,     forKey: .total))      ?? 0
        paidAmount = try? c.decode(Double.self,      forKey: .paidAmount)
        vendor     = try? c.decode(VendorRef.self,   forKey: .vendor)
        notes      = try? c.decode(String.self,      forKey: .notes)
        documents  = try? c.decode([BillDoc].self,   forKey: .documents)
    }
}

private struct ExpenseDoc: Decodable, Identifiable {
    let id: String
    let fileName: String?
}

private struct PurchaseExpense: Decodable, Identifiable {
    let id:          String
    var status:      String?
    var total:       Double
    var description: String?
    let date:        String?
    let vendor:      VendorRef?
    var notes:       String?
    let documents:   [ExpenseDoc]?

    struct VendorRef: Decodable { let name: String? }

    private enum CodingKeys: String, CodingKey {
        case id, status, total, description, date, vendor, notes, documents
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try  c.decode(String.self,        forKey: .id)
        status      = try? c.decode(String.self,        forKey: .status)
        total       = (try? c.decode(Double.self,       forKey: .total)) ?? 0
        description = try? c.decode(String.self,        forKey: .description)
        date        = try? c.decode(String.self,        forKey: .date)
        vendor      = try? c.decode(VendorRef.self,     forKey: .vendor)
        notes       = try? c.decode(String.self,        forKey: .notes)
        documents   = try? c.decode([ExpenseDoc].self,  forKey: .documents)
    }
}

private struct RecurringItem: Decodable, Identifiable {
    let id:              String
    var description:     String?
    var total:           Double
    var frequency:       String?
    var isActive:        Bool?
    let nextExpenseDate: String?
    let vendor:          VendorRef?

    struct VendorRef: Decodable { let name: String? }

    private enum CodingKeys: String, CodingKey {
        case id, description, total, frequency, isActive, nextExpenseDate, vendor
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try  c.decode(String.self,      forKey: .id)
        description     = try? c.decode(String.self,      forKey: .description)
        total           = (try? c.decode(Double.self,     forKey: .total)) ?? 0
        frequency       = try? c.decode(String.self,      forKey: .frequency)
        isActive        = try? c.decode(Bool.self,        forKey: .isActive)
        nextExpenseDate = try? c.decode(String.self,      forKey: .nextExpenseDate)
        vendor          = try? c.decode(VendorRef.self,   forKey: .vendor)
    }
}

// MARK: - Update request bodies

private struct UpdateBillRequest: Encodable {
    let status:  String?
    let dueDate: String?
    let notes:   String?
}

private struct UpdateExpenseRequest: Encodable {
    let status:      String?
    let description: String?
    let total:       Double?
    let notes:       String?
}

private struct UpdateRecurringRequest: Encodable {
    let isActive:  Bool?
    let total:     Double?
    let frequency: String?
}

// MARK: - View model

@MainActor
final class PurchasesViewModel: ObservableObject {
    @Published fileprivate var bills:      [PurchaseBill]    = []
    @Published fileprivate var expenses:   [PurchaseExpense] = []
    @Published fileprivate var recurring:  [RecurringItem]   = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        async let b: [PurchaseBill]    = (try? await APIService.shared.get("/bills"))              ?? []
        async let e: [PurchaseExpense] = (try? await APIService.shared.get("/expenses"))           ?? []
        async let r: [RecurringItem]   = (try? await APIService.shared.get("/recurring-expenses")) ?? []
        let (bills, exp, rec) = await (b, e, r)
        self.bills     = bills
        self.expenses  = exp
        self.recurring = rec
        isLoading = false
    }

    fileprivate var totalOwed:        Double { bills.filter   { $0.status != "PAID" }.reduce(0) { $0 + $1.remaining } }
    fileprivate var totalSpent:       Double { expenses.reduce(0) { $0 + $1.total } }
    fileprivate var monthlyRecurring: Double { recurring.filter { $0.isActive == true }.reduce(0) { $0 + $1.total } }
}

// MARK: - Main view

struct PurchasesView: View {
    @StateObject private var vm = PurchasesViewModel()
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedTab      = 0
    @State private var selectedBill:      PurchaseBill?    = nil
    @State private var selectedExpense:   PurchaseExpense? = nil
    @State private var selectedRecurring: RecurringItem?   = nil

    @State private var showFABMenu = false

    // Edit sheets
    @State private var editBill:      PurchaseBill?    = nil
    @State private var editExpense:   PurchaseExpense? = nil
    @State private var editRecurring: RecurringItem?   = nil

    // iPhone detail sheets
    @State private var previewBill:      PurchaseBill?    = nil
    @State private var previewExpense:   PurchaseExpense? = nil
    @State private var previewRecurring: RecurringItem?   = nil

    // Upload / scan state
    @State private var showUploadPicker  = false
    @State private var showScanCamera    = false
    @State private var uploadError:      String?
    @State private var showUploadError   = false

    @State private var isParsing         = false
    @State private var parsedForExpense: ParsedQuote?
    @State private var parsedDocId:      String?
    @State private var showNewExpense    = false

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    iPadLayout
                } else {
                    iPhoneLayout
                }
            }
            .navigationTitle("Purchases")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await vm.load() }
            .task { await vm.load() }
        }
        .confirmationDialog("Add to Purchases", isPresented: $showFABMenu, titleVisibility: .visible) {
            Button("Scan Receipt / Invoice")  { showScanCamera   = true }
            Button("Upload Receipt / Invoice") { showUploadPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showScanCamera) {
            DocumentCameraView(
                onScan: { images in
                    showScanCamera = false
                    Task { await parseScannedForExpense(images) }
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
                Task { await parseUploadedForExpense(url: url) }
            }
        }
        .alert("Upload Error", isPresented: $showUploadError) { Button("OK") {} }
            message: { Text(uploadError ?? "Upload failed.") }
        .sheet(isPresented: $showNewExpense, onDismiss: { Task { await vm.load() } }) {
            NewExpenseFromSupplierSheet(
                presetSupplier: nil,
                parsed:         parsedForExpense,
                docId:          parsedDocId,
                isPresented:    $showNewExpense
            )
        }
        .sheet(item: $editBill) { bill in
            EditBillSheet(bill: bill) { updated in applyBillUpdate(updated) }
        }
        .sheet(item: $editExpense) { exp in
            EditExpenseSheet(expense: exp) { updated in applyExpenseUpdate(updated) }
        }
        .sheet(item: $editRecurring) { rec in
            EditRecurringSheet(item: rec) { updated in applyRecurringUpdate(updated) }
        }
        // iPhone preview sheets
        .sheet(item: $previewBill) { bill in
            BillPreviewSheet(bill: bill) { updated in applyBillUpdate(updated) }
        }
        .sheet(item: $previewExpense) { exp in
            ExpensePreviewSheet(expense: exp) { updated in applyExpenseUpdate(updated) }
        }
        .sheet(item: $previewRecurring) { rec in
            RecurringPreviewSheet(item: rec) { updated in applyRecurringUpdate(updated) }
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
    }

    // MARK: - iPad split layout

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            // Left panel: list
            VStack(spacing: 0) {
                summaryBar
                Divider()
                tabPicker
                Divider()
                ZStack(alignment: .bottomTrailing) {
                    if vm.isLoading {
                        ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        switch selectedTab {
                        case 0:  iPadBillsList
                        case 1:  iPadExpensesList
                        default: iPadRecurringList
                        }
                    }
                    FABButton { showFABMenu = true }
                        .padding(.trailing, 16).padding(.bottom, 24)
                }
            }
            .frame(width: 360)
            .background(Color(.systemGroupedBackground))

            Divider()

            // Right panel: document / detail
            switch selectedTab {
            case 0:
                if let bill = selectedBill {
                    billRightPanel(bill)
                } else {
                    rightEmptyState(icon: "doc.text", label: "Select a bill to view details")
                }
            case 1:
                if let expense = selectedExpense {
                    expenseRightPanel(expense)
                } else {
                    rightEmptyState(icon: "creditcard", label: "Select an expense to preview")
                }
            default:
                if let item = selectedRecurring {
                    recurringRightPanel(item)
                } else {
                    rightEmptyState(icon: "arrow.clockwise", label: "Select a recurring expense to view details")
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()
            tabPicker
            Divider()
            ZStack(alignment: .bottomTrailing) {
                if vm.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch selectedTab {
                    case 0:  iPhoneBillsList
                    case 1:  iPhoneExpensesList
                    default: iPhoneRecurringList
                    }
                }
                FABButton { showFABMenu = true }
                    .padding(.trailing, 20).padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Shared header subviews

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryCell(label: "Bills Owed",   value: vm.totalOwed,        color: .red)
            Divider().frame(height: 40)
            summaryCell(label: "Total Spent",  value: vm.totalSpent,       color: .primary)
            Divider().frame(height: 40)
            summaryCell(label: "Recurring/mo", value: vm.monthlyRecurring, color: .orange)
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("Bills (\(vm.bills.count))").tag(0)
            Text("Expenses (\(vm.expenses.count))").tag(1)
            Text("Recurring (\(vm.recurring.count))").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - iPad lists

    private var iPadBillsList: some View {
        Group {
            if vm.bills.isEmpty {
                EmptyStateView(icon: "doc.text", title: "No Bills",
                               message: "Bills from your vendors will appear here.")
            } else {
                List(vm.bills) { bill in
                    Button { selectedBill = bill } label: {
                        purchaseBillRow(bill)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedBill?.id == bill.id
                            ? Color(.systemGray5) : Color.clear
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    private var iPadExpensesList: some View {
        Group {
            if vm.expenses.isEmpty {
                EmptyStateView(icon: "creditcard", title: "No Expenses",
                               message: "Your expense records will appear here.")
            } else {
                List(vm.expenses) { expense in
                    Button { selectedExpense = expense } label: {
                        purchaseExpenseRow(expense)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedExpense?.id == expense.id
                            ? Color(.systemGray5) : Color.clear
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    private var iPadRecurringList: some View {
        Group {
            if vm.recurring.isEmpty {
                EmptyStateView(icon: "arrow.clockwise", title: "No Recurring Expenses",
                               message: "Set up recurring expenses to track subscriptions and regular bills.")
            } else {
                List(vm.recurring) { item in
                    Button { selectedRecurring = item } label: {
                        purchaseRecurringRow(item)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedRecurring?.id == item.id
                            ? Color(.systemGray5) : Color.clear
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - iPhone lists

    private var iPhoneBillsList: some View {
        Group {
            if vm.bills.isEmpty {
                EmptyStateView(icon: "doc.text", title: "No Bills",
                               message: "Bills from your vendors will appear here.")
            } else {
                List(vm.bills) { bill in
                    purchaseBillRow(bill)
                        .contentShape(Rectangle())
                        .onTapGesture { previewBill = bill }
                }
                .listStyle(.plain)
            }
        }
    }

    private var iPhoneExpensesList: some View {
        Group {
            if vm.expenses.isEmpty {
                EmptyStateView(icon: "creditcard", title: "No Expenses",
                               message: "Your expense records will appear here.")
            } else {
                List(vm.expenses) { expense in
                    purchaseExpenseRow(expense)
                        .contentShape(Rectangle())
                        .onTapGesture { previewExpense = expense }
                }
                .listStyle(.plain)
            }
        }
    }

    private var iPhoneRecurringList: some View {
        Group {
            if vm.recurring.isEmpty {
                EmptyStateView(icon: "arrow.clockwise", title: "No Recurring Expenses",
                               message: "Set up recurring expenses to track subscriptions and regular bills.")
            } else {
                List(vm.recurring) { item in
                    purchaseRecurringRow(item)
                        .contentShape(Rectangle())
                        .onTapGesture { previewRecurring = item }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Row views

    @ViewBuilder
    private func purchaseBillRow(_ bill: PurchaseBill) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.vendor?.name ?? bill.number ?? "Bill")
                    .font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 6) {
                    if let status = bill.status {
                        Text(status.capitalized)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(billStatusColor(status).opacity(0.15), in: Capsule())
                            .foregroundStyle(billStatusColor(status))
                    }
                    if let due = bill.dueDate {
                        Text(shortDate(due)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(bill.total, format: .currency(code: "ZAR").presentation(.narrow))
                    .font(.subheadline.bold())
                if bill.paidAmount ?? 0 > 0 {
                    Text("\(bill.remaining, format: .currency(code: "ZAR").presentation(.narrow)) remaining")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func purchaseExpenseRow(_ expense: PurchaseExpense) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.vendor?.name ?? expense.description ?? "Expense")
                    .font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 6) {
                    if let status = expense.status {
                        Text(status.capitalized)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(expenseStatusColor(status).opacity(0.15), in: Capsule())
                            .foregroundStyle(expenseStatusColor(status))
                    }
                    if let d = expense.date {
                        Text(shortDate(d)).font(.caption).foregroundStyle(.secondary)
                    }
                    if expense.documents?.isEmpty == false {
                        Image(systemName: "paperclip")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Text(expense.total, format: .currency(code: "ZAR").presentation(.narrow))
                    .font(.subheadline.bold())
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func purchaseRecurringRow(_ item: RecurringItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((item.isActive == true ? Color.orange : Color.gray).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.isActive == true ? .orange : .secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.vendor?.name ?? item.description ?? "Recurring")
                    .font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 6) {
                    if let freq = item.frequency {
                        Text(freq.capitalized)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Text(item.isActive == true ? "Active" : "Inactive")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let next = item.nextExpenseDate {
                    Text("Next: \(shortDate(next))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Text(item.total, format: .currency(code: "ZAR").presentation(.narrow))
                    .font(.subheadline.bold())
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - iPad right panels

    private func billRightPanel(_ bill: PurchaseBill) -> some View {
        VStack(spacing: 0) {
            panelToolbar { editBill = bill }
            Divider()
            ScrollView {
                BillDetailCard(bill: bill)
                    .padding(24)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func expenseRightPanel(_ expense: PurchaseExpense) -> some View {
        VStack(spacing: 0) {
            panelToolbar { editExpense = expense }
            Divider()
            if let docId = expense.documents?.first?.id {
                // Expense summary strip + full document viewer below
                VStack(spacing: 0) {
                    expenseSummaryStrip(expense)
                    Divider()
                    DocumentViewerView(documentId: docId)
                }
            } else {
                ScrollView {
                    ExpenseDetailCard(expense: expense)
                        .padding(24)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private func recurringRightPanel(_ item: RecurringItem) -> some View {
        VStack(spacing: 0) {
            panelToolbar { editRecurring = item }
            Divider()
            ScrollView {
                RecurringDetailCard(item: item)
                    .padding(24)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func panelToolbar(onEdit: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("Edit", action: onEdit)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func expenseSummaryStrip(_ expense: PurchaseExpense) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.vendor?.name ?? expense.description ?? "Expense")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let d = expense.date {
                    Text(shortDate(d)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let status = expense.status {
                Text(status.capitalized)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(expenseStatusColor(status).opacity(0.15), in: Capsule())
                    .foregroundStyle(expenseStatusColor(status))
            }
            Text(expense.total, format: .currency(code: "ZAR"))
                .font(.system(size: 15, weight: .heavy))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func rightEmptyState(icon: String, label: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Color(.systemGray4))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Update helpers

    private func applyBillUpdate(_ updated: PurchaseBill) {
        if let idx = vm.bills.firstIndex(where: { $0.id == updated.id }) { vm.bills[idx] = updated }
        if selectedBill?.id == updated.id { selectedBill = updated }
    }

    private func applyExpenseUpdate(_ updated: PurchaseExpense) {
        if let idx = vm.expenses.firstIndex(where: { $0.id == updated.id }) { vm.expenses[idx] = updated }
        if selectedExpense?.id == updated.id { selectedExpense = updated }
    }

    private func applyRecurringUpdate(_ updated: RecurringItem) {
        if let idx = vm.recurring.firstIndex(where: { $0.id == updated.id }) { vm.recurring[idx] = updated }
        if selectedRecurring?.id == updated.id { selectedRecurring = updated }
    }

    // MARK: - Scan / upload

    private func parseScannedForExpense(_ images: [UIImage]) async {
        isParsing = true
        do {
            let parsed = try await DocumentService.shared.parseVendorQuote(images: images)
            let doc    = try? await DocumentService.shared.uploadScan(images: images, type: .receipt)
            parsedForExpense = parsed
            parsedDocId      = doc?.id
            isParsing        = false
            showNewExpense   = true
        } catch {
            isParsing        = false
            parsedForExpense = nil
            parsedDocId      = nil
            showNewExpense   = true
        }
    }

    private func parseUploadedForExpense(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        isParsing = true
        do {
            let data     = try Data(contentsOf: url)
            let mimeType = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg"
            let parsed   = try await DocumentService.shared.parseVendorQuoteFromData(data, mimeType: mimeType)
            let doc      = try? await DocumentService.shared.uploadFile(
                data: data, fileName: url.lastPathComponent,
                mimeType: mimeType, type: .receipt
            )
            parsedForExpense = parsed
            parsedDocId      = doc?.id
            isParsing        = false
            showNewExpense   = true
        } catch {
            isParsing        = false
            parsedForExpense = nil
            parsedDocId      = nil
            showNewExpense   = true
        }
    }

    // MARK: - Helpers

    private func summaryCell(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(fmtShort(value))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold)).tracking(0.5)
                .foregroundStyle(.secondary).textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private func fmtShort(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "R%.1fM", v / 1_000_000) }
        if v >= 1_000     { return "R\(Int(v / 1_000))k" }
        return "R\(Int(v))"
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withFullDate]
        guard let d = f.date(from: iso) ?? f2.date(from: iso) else { return iso }
        return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
    }

    private func billStatusColor(_ s: String) -> Color {
        switch s {
        case "PAID": return .green; case "OVERDUE": return .red; case "PENDING": return .orange
        default: return .gray
        }
    }

    private func expenseStatusColor(_ s: String) -> Color {
        switch s {
        case "PAID": return .green; case "OVERDUE": return .red; case "UNPAID": return .orange
        default: return .gray
        }
    }
}

// MARK: - Bill detail card

private struct BillDetailCard: View {
    let bill: PurchaseBill

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(bill.vendor?.name ?? bill.number ?? "Bill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text("BILL")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .background(Color.orange)

            // Sub-header
            HStack {
                Text(bill.number ?? "—")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if let status = bill.status {
                    Text(status.capitalized)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(billColor(status).opacity(0.15), in: Capsule())
                        .foregroundStyle(billColor(status))
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(.systemGray6))

            // Amounts
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    detailPair(label: "TOTAL", value: formatted(bill.total))
                    if let paid = bill.paidAmount, paid > 0 {
                        detailPair(label: "PAID", value: formatted(paid))
                        detailPair(label: "REMAINING", value: formatted(bill.remaining))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 16)

                Divider()

                VStack(alignment: .trailing, spacing: 6) {
                    if let due = bill.dueDate { detailPair(label: "DUE DATE", value: shortDate(due)) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 24).padding(.vertical, 16)
            }

            if let notes = bill.notes, !notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    Text(notes).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle().fill(Color.orange.opacity(0.2)).frame(height: 4)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    private func detailPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold))
        }
    }

    private func formatted(_ v: Double) -> String {
        v.formatted(.currency(code: "ZAR"))
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        if let d = f.date(from: iso) {
            return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
        }
        return iso
    }

    private func billColor(_ s: String) -> Color {
        switch s {
        case "PAID": return .green; case "OVERDUE": return .red; case "PENDING": return .orange
        default: return .gray
        }
    }
}

// MARK: - Expense detail card (no attachment)

private struct ExpenseDetailCard: View {
    let expense: PurchaseExpense

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(expense.vendor?.name ?? expense.description ?? "Expense")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text("EXPENSE")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .background(Color.orange)

            // Sub-header
            HStack {
                Text(expense.description ?? "—")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let status = expense.status {
                    Text(status.capitalized)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(statusColor(status).opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor(status))
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(.systemGray6))

            // Details
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if let vendor = expense.vendor?.name {
                        detailPair(label: "VENDOR", value: vendor)
                    }
                    if let desc = expense.description {
                        detailPair(label: "DESCRIPTION", value: desc)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 16)

                Divider()

                VStack(alignment: .trailing, spacing: 6) {
                    if let d = expense.date { detailPair(label: "DATE", value: shortDate(d)) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 24).padding(.vertical, 16)
            }

            Divider()

            // Amount row
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("TOTAL")
                            .font(.system(size: 13, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(.orange)
                        Text(expense.total, format: .currency(code: "ZAR"))
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(width: 240)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)

            if let notes = expense.notes, !notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    Text(notes).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle().fill(Color.orange.opacity(0.2)).frame(height: 4)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    private func detailPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold))
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withFullDate]
        guard let d = f.date(from: iso) ?? f2.date(from: iso) else { return iso }
        return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "PAID": return .green; case "OVERDUE": return .red; case "UNPAID": return .orange
        default: return .gray
        }
    }
}

// MARK: - Recurring detail card

private struct RecurringDetailCard: View {
    let item: RecurringItem

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(item.vendor?.name ?? item.description ?? "Recurring")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text("RECURRING")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .background(Color.orange)

            HStack {
                if let freq = item.frequency {
                    Text(freq.capitalized)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.isActive == true ? "Active" : "Inactive")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((item.isActive == true ? Color.green : Color.gray).opacity(0.15), in: Capsule())
                    .foregroundStyle(item.isActive == true ? Color.green : Color.gray)
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(.systemGray6))

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if let desc = item.description {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DESCRIPTION").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                            Text(desc).font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 16)

                Divider()

                VStack(alignment: .trailing, spacing: 6) {
                    if let next = item.nextExpenseDate {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("NEXT DATE").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                            Text(shortDate(next)).font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 24).padding(.vertical, 16)
            }

            Divider()

            HStack {
                Spacer()
                HStack(spacing: 16) {
                    Text("AMOUNT")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.5).foregroundStyle(.orange)
                    Text(item.total, format: .currency(code: "ZAR"))
                        .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.orange)
                }
                .frame(width: 240)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)

            Rectangle().fill(Color.orange.opacity(0.2)).frame(height: 4)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withFullDate]
        guard let d = f.date(from: iso) ?? f2.date(from: iso) else { return iso }
        return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
    }
}

// MARK: - iPhone preview sheets

private struct BillPreviewSheet: View {
    @State var bill: PurchaseBill
    var onUpdated: (PurchaseBill) -> Void = { _ in }
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                BillDetailCard(bill: bill).padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(bill.vendor?.name ?? bill.number ?? "Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showEdit) {
                EditBillSheet(bill: bill) { updated in bill = updated; onUpdated(updated) }
            }
        }
    }
}

private struct ExpensePreviewSheet: View {
    @State var expense: PurchaseExpense
    var onUpdated: (PurchaseExpense) -> Void = { _ in }
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let docId = expense.documents?.first?.id {
                    VStack(spacing: 0) {
                        expenseSummaryStrip
                        Divider()
                        DocumentViewerView(documentId: docId)
                    }
                } else {
                    ScrollView {
                        ExpenseDetailCard(expense: expense).padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle(expense.vendor?.name ?? expense.description ?? "Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showEdit) {
                EditExpenseSheet(expense: expense) { updated in expense = updated; onUpdated(updated) }
            }
        }
    }

    private var expenseSummaryStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.vendor?.name ?? expense.description ?? "Expense")
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if let d = expense.date {
                    Text(shortDate(d)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let status = expense.status {
                Text(status.capitalized)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor(status).opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor(status))
            }
            Text(expense.total, format: .currency(code: "ZAR"))
                .font(.system(size: 15, weight: .heavy))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withFullDate]
        guard let d = f.date(from: iso) ?? f2.date(from: iso) else { return iso }
        return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "PAID": return .green; case "OVERDUE": return .red; case "UNPAID": return .orange
        default: return .gray
        }
    }
}

private struct RecurringPreviewSheet: View {
    @State var item: RecurringItem
    var onUpdated: (RecurringItem) -> Void = { _ in }
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                RecurringDetailCard(item: item).padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(item.vendor?.name ?? item.description ?? "Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showEdit) {
                EditRecurringSheet(item: item) { updated in item = updated; onUpdated(updated) }
            }
        }
    }
}

// MARK: - Edit Bill Sheet

private struct EditBillSheet: View {
    let bill:    PurchaseBill
    let onSaved: (PurchaseBill) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var status:    String
    @State private var dueDateOn: Bool
    @State private var dueDate:   Date
    @State private var notes:     String
    @State private var saving     = false
    @State private var error      = ""

    private let statuses = ["DRAFT", "PENDING", "PAID", "OVERDUE"]

    init(bill: PurchaseBill, onSaved: @escaping (PurchaseBill) -> Void) {
        self.bill    = bill
        self.onSaved = onSaved
        _status    = State(initialValue: bill.status ?? "PENDING")
        _dueDateOn = State(initialValue: bill.dueDate != nil)
        _notes     = State(initialValue: bill.notes ?? "")
        let parsed: Date = {
            guard let s = bill.dueDate else { return Date() }
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            return f.date(from: s) ?? Date()
        }()
        _dueDate = State(initialValue: parsed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vendor") {
                    LabeledContent("Name", value: bill.vendor?.name ?? bill.number ?? "—")
                    LabeledContent("Total", value: bill.total, format: .currency(code: "ZAR"))
                }
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Due Date") {
                    Toggle("Set due date", isOn: $dueDateOn.animation())
                    if dueDateOn { DatePicker("Due date", selection: $dueDate, displayedComponents: .date) }
                }
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(3)
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle("Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                    }.disabled(saving)
                }
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        let dueDateStr: String? = dueDateOn
            ? { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f.string(from: dueDate) }()
            : nil
        let body = UpdateBillRequest(status: status, dueDate: dueDateStr, notes: notes.isEmpty ? nil : notes)
        var updated = bill
        updated.status  = body.status
        updated.dueDate = body.dueDate
        updated.notes   = body.notes
        let _: [String: String] = (try? await APIService.shared.patch("/bills/\(bill.id)", body: body)) ?? [:]
        onSaved(updated)
        saving = false
        dismiss()
    }
}

// MARK: - Edit Expense Sheet

private struct EditExpenseSheet: View {
    let expense: PurchaseExpense
    let onSaved: (PurchaseExpense) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var status:      String
    @State private var description: String
    @State private var totalStr:    String
    @State private var notes:       String
    @State private var saving       = false
    @State private var error        = ""

    private let statuses = ["UNPAID", "PAID", "OVERDUE"]

    init(expense: PurchaseExpense, onSaved: @escaping (PurchaseExpense) -> Void) {
        self.expense = expense
        self.onSaved = onSaved
        _status      = State(initialValue: expense.status ?? "UNPAID")
        _description = State(initialValue: expense.description ?? "")
        _totalStr    = State(initialValue: String(format: "%.2f", expense.total))
        _notes       = State(initialValue: expense.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let vendor = expense.vendor?.name {
                    Section("Vendor") { LabeledContent("Name", value: vendor) }
                }
                Section("Details") {
                    TextField("Description", text: $description)
                    HStack {
                        Text("Amount (ZAR)"); Spacer()
                        TextField("0.00", text: $totalStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
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
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                    }.disabled(saving)
                }
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        let body = UpdateExpenseRequest(
            status:      status,
            description: description.isEmpty ? nil : description,
            total:       Double(totalStr),
            notes:       notes.isEmpty ? nil : notes
        )
        var updated = expense
        updated.status      = body.status
        updated.description = body.description
        updated.total       = body.total ?? expense.total
        updated.notes       = body.notes
        let _: [String: String] = (try? await APIService.shared.patch("/expenses/\(expense.id)", body: body)) ?? [:]
        onSaved(updated)
        saving = false
        dismiss()
    }
}

// MARK: - Edit Recurring Sheet

private struct EditRecurringSheet: View {
    let item:    RecurringItem
    let onSaved: (RecurringItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isActive:  Bool
    @State private var totalStr:  String
    @State private var frequency: String
    @State private var saving     = false
    @State private var error      = ""

    private let frequencies = ["DAILY", "WEEKLY", "MONTHLY", "QUARTERLY", "ANNUALLY"]

    init(item: RecurringItem, onSaved: @escaping (RecurringItem) -> Void) {
        self.item    = item
        self.onSaved = onSaved
        _isActive   = State(initialValue: item.isActive ?? true)
        _totalStr   = State(initialValue: String(format: "%.2f", item.total))
        _frequency  = State(initialValue: item.frequency ?? "MONTHLY")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let name = item.vendor?.name ?? item.description {
                    Section("Item") { LabeledContent("Name", value: name) }
                }
                Section("Schedule") {
                    Toggle("Active", isOn: $isActive).tint(.orange)
                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                Section("Amount") {
                    HStack {
                        Text("Amount (ZAR)"); Spacer()
                        TextField("0.00", text: $totalStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                if let next = item.nextExpenseDate {
                    Section("Next Occurrence") { LabeledContent("Date", value: next) }
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle("Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                    }.disabled(saving)
                }
            }
        }
    }

    private func save() async {
        saving = true; error = ""
        let body = UpdateRecurringRequest(isActive: isActive, total: Double(totalStr), frequency: frequency)
        var updated = item
        updated.isActive  = body.isActive
        updated.total     = body.total ?? item.total
        updated.frequency = body.frequency
        let _: [String: String] = (try? await APIService.shared.patch("/recurring-expenses/\(item.id)", body: body)) ?? [:]
        onSaved(updated)
        saving = false
        dismiss()
    }
}
