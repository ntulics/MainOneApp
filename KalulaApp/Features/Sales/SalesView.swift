import SwiftUI

// MARK: - View model

@MainActor
final class SalesViewModel: ObservableObject {
    @Published var invoices:        [Invoice]        = []
    @Published var quotes:          [Quote]          = []
    @Published var companySettings: CompanySettings? = nil
    @Published var isLoading = false

    func load() async {
        isLoading = true
        async let inv: [Invoice]         = (try? await APIService.shared.get("/invoices"))       ?? []
        async let quo: [Quote]           = (try? await APIService.shared.get("/quotes"))         ?? []
        async let co:  CompanySettings?  = try? await APIService.shared.get("/settings/company")
        let (i, q, c) = await (inv, quo, co)
        invoices        = i
        quotes          = q
        companySettings = c
        isLoading = false
    }

    var totalInvoiced: Double { invoices.reduce(0) { $0 + $1.total } }
    var totalReceived: Double { invoices.filter { $0.status == "PAID" }.reduce(0) { $0 + $1.total } }
    var outstanding:   Double { invoices.filter { ["DRAFT","SENT","OVERDUE"].contains($0.status) }.reduce(0) { $0 + $1.total } }
}

// MARK: - Main view

struct SalesView: View {
    @StateObject private var vm = SalesViewModel()
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedTab     = 0
    @State private var selectedInvoice: Invoice? = nil
    @State private var selectedQuote:   Quote?   = nil
    @State private var showNewInvoice  = false
    @State private var showNewQuote    = false
    @State private var previewInvoice: Invoice? = nil
    @State private var previewQuote:   Quote?   = nil

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    iPadLayout
                } else {
                    iPhoneLayout
                }
            }
            .navigationTitle("Sales")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await vm.load() }
            .task { await vm.load() }
        }
        .sheet(isPresented: $showNewInvoice, onDismiss: { Task { await vm.load() } }) {
            NewInvoiceSheet(isPresented: $showNewInvoice)
        }
        .sheet(isPresented: $showNewQuote, onDismiss: { Task { await vm.load() } }) {
            NewQuoteSheet(isPresented: $showNewQuote)
        }
        .sheet(item: $previewInvoice) { inv in
            InvoicePreviewSheet(invoice: inv, company: vm.companySettings) { updated in
                applyInvoiceUpdate(updated)
            }
        }
        .sheet(item: $previewQuote) { quo in
            QuotePreviewSheet(quote: quo, company: vm.companySettings) { updated in
                applyQuoteUpdate(updated)
            }
        }
    }

    // MARK: - iPad split layout

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                summaryBar
                Divider()
                tabPicker
                Divider()
                ZStack(alignment: .bottomTrailing) {
                    if vm.isLoading {
                        ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if selectedTab == 0 {
                        iPadInvoiceList
                    } else {
                        iPadQuoteList
                    }
                    FABButton {
                        if selectedTab == 0 { showNewInvoice = true }
                        else               { showNewQuote   = true }
                    }
                    .padding(.trailing, 16).padding(.bottom, 24)
                }
            }
            .frame(width: 360)
            .background(Color(.systemGroupedBackground))

            Divider()

            if selectedTab == 0 {
                if let inv = selectedInvoice {
                    invoiceDocPanel(inv)
                } else {
                    docEmptyState(icon: "doc.text", label: "Select an invoice to preview")
                }
            } else {
                if let quo = selectedQuote {
                    quoteDocPanel(quo)
                } else {
                    docEmptyState(icon: "list.clipboard", label: "Select a quote to preview")
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
                } else if selectedTab == 0 {
                    iPhoneInvoiceList
                } else {
                    iPhoneQuoteList
                }
                FABButton {
                    if selectedTab == 0 { showNewInvoice = true }
                    else               { showNewQuote   = true }
                }
                .padding(.trailing, 20).padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Shared header subviews

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryCell(label: "Invoiced",    value: vm.totalInvoiced, color: .primary)
            Divider().frame(height: 40)
            summaryCell(label: "Received",    value: vm.totalReceived, color: .green)
            Divider().frame(height: 40)
            summaryCell(label: "Outstanding", value: vm.outstanding,   color: .orange)
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("Invoices (\(vm.invoices.count))").tag(0)
            Text("Quotes (\(vm.quotes.count))").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - iPad lists (tap to select)

    private var iPadInvoiceList: some View {
        Group {
            if vm.invoices.isEmpty {
                EmptyStateView(icon: "doc.text", title: "No Invoices",
                               message: "Create your first invoice using the + button.")
            } else {
                List {
                    ForEach(vm.invoices) { invoice in
                        Button { selectedInvoice = invoice } label: {
                            InvoiceRow(invoice: invoice)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedInvoice?.id == invoice.id
                                ? Color(.systemGray5) : Color.clear
                        )
                    }
                    .onDelete { idx in
                        let items = idx.map { vm.invoices[$0] }
                        Task { for inv in items { await deleteInvoice(inv) } }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var iPadQuoteList: some View {
        Group {
            if vm.quotes.isEmpty {
                EmptyStateView(icon: "list.clipboard", title: "No Quotes",
                               message: "Create a quote using the + button.")
            } else {
                List {
                    ForEach(vm.quotes) { quote in
                        Button { selectedQuote = quote } label: {
                            QuoteRow(quote: quote)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedQuote?.id == quote.id
                                ? Color(.systemGray5) : Color.clear
                        )
                    }
                    .onDelete { idx in
                        let items = idx.map { vm.quotes[$0] }
                        Task { for q in items { await deleteQuote(q) } }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - iPhone lists (tap to open sheet)

    private var iPhoneInvoiceList: some View {
        Group {
            if vm.invoices.isEmpty {
                EmptyStateView(icon: "doc.text", title: "No Invoices",
                               message: "Create your first invoice using the + button.")
            } else {
                List {
                    ForEach(vm.invoices) { invoice in
                        InvoiceRow(invoice: invoice)
                            .contentShape(Rectangle())
                            .onTapGesture { previewInvoice = invoice }
                    }
                    .onDelete { idx in
                        let items = idx.map { vm.invoices[$0] }
                        Task { for inv in items { await deleteInvoice(inv) } }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var iPhoneQuoteList: some View {
        Group {
            if vm.quotes.isEmpty {
                EmptyStateView(icon: "list.clipboard", title: "No Quotes",
                               message: "Create a quote using the + button or scan a vendor document.")
            } else {
                List {
                    ForEach(vm.quotes) { quote in
                        QuoteRow(quote: quote)
                            .contentShape(Rectangle())
                            .onTapGesture { previewQuote = quote }
                    }
                    .onDelete { idx in
                        let items = idx.map { vm.quotes[$0] }
                        Task { for q in items { await deleteQuote(q) } }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - iPad right panel

    private func invoiceDocPanel(_ invoice: Invoice) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Edit") { previewInvoice = invoice }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .background(Color(.secondarySystemGroupedBackground))
            Divider()
            ScrollView {
                InvoiceDocumentView(invoice: invoice, company: vm.companySettings)
                    .padding(24)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func quoteDocPanel(_ quote: Quote) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Edit") { previewQuote = quote }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .background(Color(.secondarySystemGroupedBackground))
            Divider()
            ScrollView {
                QuoteDocumentView(quote: quote, company: vm.companySettings)
                    .padding(24)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func docEmptyState(icon: String, label: String) -> some View {
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

    // MARK: - Actions

    private func deleteInvoice(_ invoice: Invoice) async {
        _ = try? await APIService.shared.delete("/invoices/\(invoice.id)")
        vm.invoices.removeAll { $0.id == invoice.id }
        if selectedInvoice?.id == invoice.id { selectedInvoice = nil }
    }

    private func deleteQuote(_ quote: Quote) async {
        try? await APIService.shared.delete("/quotes/\(quote.id)")
        vm.quotes.removeAll { $0.id == quote.id }
        if selectedQuote?.id == quote.id { selectedQuote = nil }
    }

    private func applyInvoiceUpdate(_ updated: Invoice) {
        if let idx = vm.invoices.firstIndex(where: { $0.id == updated.id }) {
            vm.invoices[idx] = updated
        }
        if selectedInvoice?.id == updated.id { selectedInvoice = updated }
    }

    private func applyQuoteUpdate(_ updated: Quote) {
        if let idx = vm.quotes.firstIndex(where: { $0.id == updated.id }) {
            vm.quotes[idx] = updated
        }
        if selectedQuote?.id == updated.id { selectedQuote = updated }
    }

    // MARK: - Helpers

    private func summaryCell(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(fmtShort(value))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private func fmtShort(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "R%.1fM", v / 1_000_000) }
        if v >= 1_000     { return "R\(Int(v / 1_000))k" }
        return "R\(Int(v))"
    }
}

// MARK: - Invoice Document View (PDF-like renderer)

struct InvoiceDocumentView: View {
    let invoice: Invoice
    let company: CompanySettings?

    private var currencyCode: String { company?.currency ?? "ZAR" }
    private var companyName:  String { company?.name     ?? "My Company" }

    var body: some View {
        VStack(spacing: 0) {
            docHeader(title: "INVOICE")
            docSubHeader(number: invoice.number) { InvoiceStatusBadge(status: invoice.status) }
            docRecipientRow(
                sectionLabel:   "BILL TO",
                recipientName:  invoice.contact?.displayName ?? invoice.projectName ?? "—",
                recipientEmail: invoice.contact?.email,
                details: {
                    if let due = invoice.dueDate { detailPair(label: "DUE DATE", value: shortDate(due)) }
                    detailPair(label: "ISSUED", value: shortDate(invoice.createdAt))
                    if let p = invoice.projectName, !p.isEmpty { detailPair(label: "PROJECT", value: p) }
                }
            )
            Divider()
            if !invoice.lineItems.isEmpty {
                lineItemsTable(invoice.lineItems)
                Divider()
            }
            totalsSection(subtotal: invoice.subtotal, tax: invoice.tax, total: invoice.total)
            if let notes = invoice.notes, !notes.isEmpty {
                Divider()
                notesSection(notes)
            }
            footerBar
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    // MARK: Document sections

    private func docHeader(title: String) -> some View {
        HStack {
            Text(companyName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.orange)
    }

    private func docSubHeader<Badge: View>(number: String, @ViewBuilder badge: () -> Badge) -> some View {
        HStack {
            Text(number)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            badge()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    private func docRecipientRow<Details: View>(
        sectionLabel: String,
        recipientName: String,
        recipientEmail: String?,
        @ViewBuilder details: () -> Details
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sectionLabel)
                    .font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(recipientName)
                    .font(.system(size: 14, weight: .semibold))
                if let email = recipientEmail {
                    Text(email).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.vertical, 16)

            Divider()

            VStack(alignment: .trailing, spacing: 6) {
                details()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
    }

    private func lineItemsTable(_ items: [LineItem]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("DESCRIPTION").tableHeaderStyle().frame(maxWidth: .infinity, alignment: .leading)
                Text("QTY").tableHeaderStyle().frame(width: 40, alignment: .trailing)
                Text("UNIT PRICE").tableHeaderStyle().frame(width: 84, alignment: .trailing)
                Text("TOTAL").tableHeaderStyle().frame(width: 84, alignment: .trailing)
            }
            .padding(.horizontal, 24).padding(.vertical, 8)
            .background(Color(.systemGray6))

            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                HStack(alignment: .top) {
                    Text(item.description)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.0f", item.quantity))
                        .font(.system(size: 13))
                        .frame(width: 40, alignment: .trailing)
                    Text(item.unitPrice, format: .currency(code: currencyCode))
                        .font(.system(size: 13))
                        .frame(width: 84, alignment: .trailing)
                    Text(item.total, format: .currency(code: currencyCode))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 84, alignment: .trailing)
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(idx.isMultiple(of: 2) ? Color.white : Color(.systemGray6).opacity(0.5))
                if idx < items.count - 1 { Divider().padding(.leading, 24) }
            }
        }
    }

    private func totalsSection(subtotal: Double, tax: Double, total: Double) -> some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                totalsRow("Subtotal", subtotal)
                if tax > 0 {
                    totalsRow("Tax", tax)
                    Divider()
                }
                HStack(spacing: 16) {
                    Text("TOTAL")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(.orange)
                    Text(total, format: .currency(code: currencyCode))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 240)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func totalsRow(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 16) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode)).font(.system(size: 12))
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(.system(size: 9, weight: .bold)).tracking(1)
                .foregroundStyle(.secondary)
            Text(notes).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerBar: some View {
        Rectangle().fill(Color.orange.opacity(0.2)).frame(height: 4)
    }

    private func detailPair(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold))
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        if let d = f.date(from: iso) {
            return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
        }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
        }
        return iso
    }
}

// MARK: - Quote Document View (PDF-like renderer)

struct QuoteDocumentView: View {
    let quote: Quote
    let company: CompanySettings?

    private var currencyCode: String { company?.currency ?? "ZAR" }
    private var companyName:  String { company?.name     ?? "My Company" }

    var body: some View {
        VStack(spacing: 0) {
            docHeader(title: "QUOTE")
            docSubHeader(number: quote.number) { StatusBadge(status: quote.status) }
            docRecipientRow(
                sectionLabel:   "PREPARED FOR",
                recipientName:  quote.contact?.displayName ?? quote.projectName ?? "—",
                recipientEmail: quote.contact?.email,
                details: {
                    if let valid = quote.validUntil { detailPair(label: "VALID UNTIL", value: shortDate(valid)) }
                    detailPair(label: "ISSUED", value: shortDate(quote.createdAt))
                    if let p = quote.projectName, !p.isEmpty { detailPair(label: "PROJECT", value: p) }
                }
            )
            Divider()
            if !quote.lineItems.isEmpty {
                lineItemsTable(quote.lineItems)
                Divider()
            }
            totalsSection(subtotal: quote.subtotal, tax: quote.tax, total: quote.total)
            if let notes = quote.notes, !notes.isEmpty {
                Divider()
                notesSection(notes)
            }
            footerBar
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    private func docHeader(title: String) -> some View {
        HStack {
            Text(companyName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.orange)
    }

    private func docSubHeader<Badge: View>(number: String, @ViewBuilder badge: () -> Badge) -> some View {
        HStack {
            Text(number)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            badge()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
    }

    private func docRecipientRow<Details: View>(
        sectionLabel: String,
        recipientName: String,
        recipientEmail: String?,
        @ViewBuilder details: () -> Details
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sectionLabel)
                    .font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(recipientName)
                    .font(.system(size: 14, weight: .semibold))
                if let email = recipientEmail {
                    Text(email).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.vertical, 16)

            Divider()

            VStack(alignment: .trailing, spacing: 6) {
                details()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
    }

    private func lineItemsTable(_ items: [LineItem]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("DESCRIPTION").tableHeaderStyle().frame(maxWidth: .infinity, alignment: .leading)
                Text("QTY").tableHeaderStyle().frame(width: 40, alignment: .trailing)
                Text("UNIT PRICE").tableHeaderStyle().frame(width: 84, alignment: .trailing)
                Text("TOTAL").tableHeaderStyle().frame(width: 84, alignment: .trailing)
            }
            .padding(.horizontal, 24).padding(.vertical, 8)
            .background(Color(.systemGray6))

            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                HStack(alignment: .top) {
                    Text(item.description)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.0f", item.quantity))
                        .font(.system(size: 13))
                        .frame(width: 40, alignment: .trailing)
                    Text(item.unitPrice, format: .currency(code: currencyCode))
                        .font(.system(size: 13))
                        .frame(width: 84, alignment: .trailing)
                    Text(item.total, format: .currency(code: currencyCode))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 84, alignment: .trailing)
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(idx.isMultiple(of: 2) ? Color.white : Color(.systemGray6).opacity(0.5))
                if idx < items.count - 1 { Divider().padding(.leading, 24) }
            }
        }
    }

    private func totalsSection(subtotal: Double, tax: Double, total: Double) -> some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                totalsRow("Subtotal", subtotal)
                if tax > 0 {
                    totalsRow("Tax", tax)
                    Divider()
                }
                HStack(spacing: 16) {
                    Text("TOTAL")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(.orange)
                    Text(total, format: .currency(code: currencyCode))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 240)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func totalsRow(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 16) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode)).font(.system(size: 12))
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(.system(size: 9, weight: .bold)).tracking(1)
                .foregroundStyle(.secondary)
            Text(notes).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerBar: some View {
        Rectangle().fill(Color.orange.opacity(0.2)).frame(height: 4)
    }

    private func detailPair(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold))
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        if let d = f.date(from: iso) {
            return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
        }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none)
        }
        return iso
    }
}

// MARK: - Table header style

private extension Text {
    func tableHeaderStyle() -> some View {
        self.font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
    }
}

// MARK: - Invoice preview sheet (iPhone)

struct InvoicePreviewSheet: View {
    @State var invoice: Invoice
    var company: CompanySettings?
    var onUpdated: (Invoice) -> Void = { _ in }
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                InvoiceDocumentView(invoice: invoice, company: company)
                    .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Invoice \(invoice.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showEdit) {
                EditInvoiceSheet(invoice: invoice, isPresented: $showEdit) { updated in
                    invoice = updated
                    onUpdated(updated)
                }
            }
        }
    }
}

// MARK: - Quote preview sheet (iPhone)

struct QuotePreviewSheet: View {
    @State var quote: Quote
    var company: CompanySettings?
    var onUpdated: (Quote) -> Void = { _ in }
    @State private var showEdit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                QuoteDocumentView(quote: quote, company: company)
                    .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Quote \(quote.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showEdit) {
                EditQuoteSheet(quote: quote, isPresented: $showEdit) { updated in
                    quote = updated
                    onUpdated(updated)
                }
            }
        }
    }
}
