import SwiftUI

// MARK: - View Model

private struct ReceiptItem: Decodable { let total: Double? }

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var invoices: [Invoice] = []
    @Published var quotes:   [Quote]   = []
    @Published var isLoading = false
    private var loaded = false

    // Financial metrics
    var revenue: Double {
        invoices.filter { inv in inv.status == "PAID" }
                .reduce(0.0) { acc, inv in acc + inv.total }
    }
    var outstanding: Double {
        invoices.filter { inv in inv.status == "SENT" }
                .reduce(0.0) { acc, inv in acc + inv.total }
    }
    var overdue: Double {
        invoices.filter { inv in inv.status == "OVERDUE" }
                .reduce(0.0) { acc, inv in acc + inv.total }
    }
    var draft: Double {
        invoices.filter { inv in inv.status == "DRAFT" }
                .reduce(0.0) { acc, inv in acc + inv.total }
    }
    var pendingQuotes: Double {
        quotes.filter { q in q.status == "SENT" }
              .reduce(0.0) { acc, q in acc + q.total }
    }

    var outstandingCount:  Int { invoices.filter { inv in inv.status == "SENT"    }.count }
    var overdueCount:      Int { invoices.filter { inv in inv.status == "OVERDUE" }.count }
    var draftCount:        Int { invoices.filter { inv in inv.status == "DRAFT"   }.count }
    var pendingQuoteCount: Int { quotes.filter   { q   in q.status   == "SENT"    }.count }

    var recentInvoices: [Invoice] { Array(invoices.prefix(6)) }

    @Published var fiscalYearEndMonth: Int = 12
    @Published var expenses: Double = 0

    var monthlyData: [(label: String, value: Double, isCurrent: Bool)] {
        let cal = Calendar.current
        let now = Date()
        let df  = DateFormatter()
        df.dateFormat = "MMM"
        let isoFull  = ISO8601DateFormatter()
        isoFull.formatOptions  = [.withInternetDateTime, .withFractionalSeconds]
        let isoShort = ISO8601DateFormatter()
        isoShort.formatOptions = [.withFullDate]

        // Fiscal year start is the month after fiscal year end
        // e.g. end=12 (Dec) → start=1 (Jan); end=2 (Feb) → start=3 (Mar)
        let fyStartMonth = fiscalYearEndMonth % 12 + 1
        let currentMonth = cal.component(.month, from: now)
        let currentYear  = cal.component(.year,  from: now)
        var fyStartYear  = currentYear
        if currentMonth < fyStartMonth { fyStartYear -= 1 }

        let fyStartDate = cal.date(from: DateComponents(year: fyStartYear, month: fyStartMonth, day: 1))!

        return (0..<12).map { offset in
            let date  = cal.date(byAdding: .month, value: offset, to: fyStartDate)!
            let month = cal.component(.month, from: date)
            let year  = cal.component(.year,  from: date)
            let label = String(df.string(from: date).prefix(3))

            let rev = invoices
                .filter { $0.status == "PAID" }
                .compactMap { inv -> Double? in
                    let d = isoFull.date(from: inv.createdAt) ?? isoShort.date(from: inv.createdAt)
                    guard let d else { return nil }
                    guard cal.component(.month, from: d) == month,
                          cal.component(.year,  from: d) == year else { return nil }
                    return inv.total
                }
                .reduce(0, +)

            let isCurrent = month == currentMonth && year == currentYear
            return (label, rev, isCurrent)
        }
    }

    func load() async {
        guard !loaded else { return }
        loaded    = true
        isLoading = true
        async let invTask:      [Invoice]          = (try? await APIService.shared.get("/invoices"))        ?? []
        async let qtTask:       [Quote]            = (try? await APIService.shared.get("/quotes"))          ?? []
        async let settingsTask: CompanySettings?   = try? await APIService.shared.get("/settings/company")
        async let receiptsTask: [ReceiptItem]      = (try? await APIService.shared.get("/receipts"))       ?? []
        let (i, q, s, r) = await (invTask, qtTask, settingsTask, receiptsTask)
        invoices  = i
        quotes    = q
        expenses  = r.reduce(0) { $0 + ($1.total ?? 0) }
        if let endMonth = s?.settings?.fiscalYearEndMonth { fiscalYearEndMonth = endMonth }
        isLoading = false
    }

    func reload() async {
        loaded    = false
        await load()
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var auth:     AuthService
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = DashboardViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                heroCard
                    .padding(.horizontal, 16)

                metricsGrid
                    .padding(.horizontal, 16)

                profitLossChart

                recentTransactions
            }
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await vm.reload() }
        .task { await vm.load() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(auth.currentUser?.displayName ?? "")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Circle()
                .fill(Color.orange.gradient)
                .frame(width: 42, height: 42)
                .overlay(
                    Text(auth.currentUser?.initials ?? "?")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                )
            Button { appState.showMore = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
        }
    }

    // MARK: - Hero Revenue Card

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            // Light-mode: deep navy — strong contrast on light grey background
            LinearGradient(
                colors: [
                    Color(red: 0.059, green: 0.090, blue: 0.165),
                    Color(red: 0.118, green: 0.176, blue: 0.294),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .opacity(colorScheme == .light ? 1 : 0)

            // Dark-mode: dark charcoal-slate — elevated above black bg without clashing
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.15),
                    Color(red: 0.17, green: 0.19, blue: 0.26),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .opacity(colorScheme == .dark ? 1 : 0)

            // Orange glow (top right)
            Circle()
                .fill(Color.orange)
                .frame(width: 180, height: 180)
                .blur(radius: 55)
                .offset(x: 40, y: -55)
                .opacity(0.28)

            // Blue/purple glow (bottom left)
            Circle()
                .fill(colorScheme == .dark ? Color.purple : Color.blue)
                .frame(width: 140, height: 140)
                .blur(radius: 65)
                .offset(x: -120, y: 60)
                .opacity(0.20)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Text("TOTAL REVENUE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(2)
                    .padding(.bottom, 10)

                if vm.isLoading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 200, height: 42)
                        .padding(.bottom, 8)
                } else {
                    Text(vm.revenue, format: .currency(code: "ZAR").presentation(.narrow))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.bottom, 6)
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Collected from paid invoices")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.bottom, 22)

                miniBarChart
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Orange accent bar at bottom
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.orange, .orange.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 6)
        .animation(.easeInOut(duration: 0.45), value: colorScheme)
    }

    // MARK: - Mini bar chart

    private var miniBarChart: some View {
        let data   = vm.monthlyData
        let maxVal = max(data.map(\.value).max() ?? 0, 1)

        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                let isCurrent = item.isCurrent
                let pct       = CGFloat(item.value / maxVal)
                let barH      = item.value > 0 ? max(6, pct * 48) : CGFloat(0)
                VStack(spacing: 4) {
                    if barH > 0 {
                        Capsule()
                            .fill(isCurrent ? Color.orange : Color.white.opacity(0.25))
                            .frame(width: 10, height: barH)
                    }
                    Text(item.label)
                        .font(.system(size: 8, weight: isCurrent ? .bold : .regular))
                        .foregroundStyle(isCurrent ? Color.orange : Color.white.opacity(0.6))
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 68, alignment: .bottom)
        .animation(.easeOut(duration: 0.5), value: vm.invoices.count)
    }

    // MARK: - Financial Overview Infographic

    private var profitLossChart: some View {
        let revenue     = vm.revenue
        let expenses    = vm.expenses
        let profit      = max(revenue - expenses, 0)
        let outstanding = vm.outstanding

        let lGrad: [Color] = [Color(red: 0, green: 0.78, blue: 1), Color(red: 0, green: 0.34, blue: 1)]
        let rGrad: [Color] = [Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.76, green: 0.50, blue: 0.98)]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Financial Overview")
                .font(.headline)
                .padding(.horizontal, 20)

            HStack(alignment: .center, spacing: 0) {

                // ── Left pills ─────────────────────────────
                VStack(spacing: 10) {
                    infoPill(num: "1", label: "Revenue",  value: revenue,
                             sub: "paid invoices", gradient: lGrad, numOnRight: true)
                    infoPill(num: "2", label: "Expenses", value: expenses,
                             sub: "total spend",   gradient: lGrad, numOnRight: true)
                }
                .frame(maxWidth: .infinity)

                // ── Left connectors ────────────────────────
                VStack(spacing: 10) {
                    infoConnector
                    infoConnector
                }
                .frame(width: 20)

                // ── Centre circle ──────────────────────────
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [.cyan, .blue, .indigo, .purple,
                                         Color(red: 0.76, green: 0.31, blue: 0.87), .cyan],
                                center: .center,
                                startAngle: .degrees(-45),
                                endAngle: .degrees(315)
                            ),
                            lineWidth: 7
                        )
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .padding(7)
                    VStack(spacing: 2) {
                        Text("FINANCIAL")
                            .font(.system(size: 7.5, weight: .black))
                            .foregroundStyle(.primary)
                            .tracking(0.4)
                        Text("OVERVIEW")
                            .font(.system(size: 6, weight: .regular))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        HStack(spacing: 2.5) {
                            ForEach([Color.cyan, .blue, .indigo, .purple,
                                     Color(red: 0.76, green: 0.31, blue: 0.87)], id: \.self) { c in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(c)
                                    .frame(width: 5.5, height: 5.5)
                            }
                        }
                        .padding(.top, 3)
                    }
                }
                .frame(width: 92, height: 92)

                // ── Right connectors ───────────────────────
                VStack(spacing: 10) {
                    infoConnector
                    infoConnector
                }
                .frame(width: 20)

                // ── Right pills ────────────────────────────
                VStack(spacing: 10) {
                    infoPill(num: "3", label: "Profit",      value: profit,
                             sub: "after costs", gradient: rGrad, numOnRight: false)
                    infoPill(num: "4", label: "Outstanding", value: outstanding,
                             sub: "pending",     gradient: rGrad, numOnRight: false)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            .padding(.horizontal, 16)
        }
    }

    private var infoConnector: some View {
        HStack(spacing: 0) {
            Circle().fill(Color(.label)).frame(width: 5, height: 5)
            Rectangle().fill(Color(.label).opacity(0.45)).frame(height: 1.5)
            Circle().fill(Color(.label)).frame(width: 5, height: 5)
        }
    }

    private func infoPill(
        num: String,
        label: String,
        value: Double,
        sub: String,
        gradient: [Color],
        numOnRight: Bool
    ) -> some View {
        HStack(spacing: 5) {
            if !numOnRight {
                numBadgeView(num)
            } else {
                Image(systemName: num == "1" ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.18), in: Circle())
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(0.5)
                    .lineLimit(1)
                Text(fmtShort(value))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 6.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if numOnRight {
                numBadgeView(num)
            } else {
                Image(systemName: num == "3" ? "dollarsign" : "clock")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.18), in: Circle())
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .background(
            LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(Capsule())
        .shadow(color: gradient[0].opacity(0.28), radius: 5, y: 3)
    }

    private func numBadgeView(_ num: String) -> some View {
        ZStack {
            Circle().fill(.white.opacity(0.22))
            Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
            Text(num)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
    }

    private func fmtShort(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "R%.1fM", v / 1_000_000) }
        if v >= 1_000 { return "R\(Int(v / 1_000))k" }
        return "R\(Int(v))"
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            DashMetricCard(
                label: "Outstanding",
                value: vm.outstanding,
                sub:   "\(vm.outstandingCount) sent",
                color: Color(red: 0, green: 0.478, blue: 1),
                icon:  "dollarsign.circle.fill"
            )
            DashMetricCard(
                label: "Overdue",
                value: vm.overdue,
                sub:   "\(vm.overdueCount) invoices",
                color: Color(red: 1, green: 0.231, blue: 0.188),
                icon:  "clock.badge.exclamationmark.fill"
            )
            DashMetricCard(
                label: "Quotes",
                value: vm.pendingQuotes,
                sub:   "\(vm.pendingQuoteCount) pending",
                color: Color(red: 0.686, green: 0.322, blue: 0.871),
                icon:  "doc.richtext.fill"
            )
            DashMetricCard(
                label: "Draft",
                value: vm.draft,
                sub:   "\(vm.draftCount) invoices",
                color: Color(red: 1, green: 0.584, blue: 0),
                icon:  "square.and.pencil"
            )
        }
    }

    // MARK: - Recent transactions

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                Spacer()
                Text("Sales tab →")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 20)

            if vm.isLoading && vm.recentInvoices.isEmpty {
                loadingRows
                    .padding(.horizontal, 16)
            } else if vm.recentInvoices.isEmpty {
                emptyTransactions
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.recentInvoices.enumerated()), id: \.element.id) { idx, invoice in
                        TransactionRow(invoice: invoice)
                        if idx < vm.recentInvoices.count - 1 {
                            Divider()
                                .padding(.leading, 74)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                .padding(.horizontal, 16)
            }
        }
    }

    private var loadingRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color(.systemFill))
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                            .frame(width: 120, height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                            .frame(width: 80, height: 10)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(width: 70, height: 13)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                Divider().padding(.leading, 74)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .redacted(reason: .placeholder)
    }

    private var emptyTransactions: some View {
        VStack(spacing: 12) {
            Image(systemName: "banknote")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.orange.opacity(0.7))
                .frame(width: 60, height: 60)
                .background(Color.orange.opacity(0.1), in: Circle())
            Text("No transactions yet")
                .font(.subheadline.bold())
            Text("Create your first invoice from the Sales tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Helpers

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        default:      return "Good evening,"
        }
    }
}

// MARK: - Metric card

struct DashMetricCard: View {
    let label: String
    let value: Double
    let sub:   String
    let color: Color
    let icon:  String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            Text(shortValue)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    private var shortValue: String {
        if value >= 1_000_000 {
            return String(format: "R%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return "R\(Int(value / 1_000))k"
        } else {
            return value.formatted(.currency(code: "ZAR").presentation(.narrow))
        }
    }
}

// MARK: - Transaction row

struct TransactionRow: View {
    let invoice: Invoice

    var body: some View {
        HStack(spacing: 14) {
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
                    Text(invoice.status.capitalized)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(statusColor)
                    Text(invoice.number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(invoice.total, format: .currency(code: "ZAR").presentation(.narrow))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(invoice.status == "PAID" ? Color.green : Color.primary)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
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
        case "SENT":     return Color(red: 0, green: 0.478, blue: 1)
        case "PAID":     return .green
        case "OVERDUE":  return Color(red: 1, green: 0.231, blue: 0.188)
        case "CANCELLED": return Color(.systemGray3)
        default:         return Color(.systemGray)
        }
    }
}

// Keep AvatarView for other files
struct AvatarView: View {
    let initials: String
    var size: CGFloat = 36

    var body: some View {
        Text(initials)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.orange, in: Circle())
    }
}
