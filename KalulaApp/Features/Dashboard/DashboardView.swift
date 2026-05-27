import SwiftUI

// MARK: - Private models

private struct PurchasesSummary: Decodable {
    let totalExpenses: Double
    let paidBills:     Double
}

struct DashBill: Decodable, Identifiable {
    let id:         String
    let number:     String?
    let status:     String?
    let dueDate:    String?
    let total:      Double
    let paidAmount: Double?
    let vendor:     Vendor?

    struct Vendor: Decodable { let name: String? }

    private enum CodingKeys: String, CodingKey {
        case id, number, status, dueDate, total, paidAmount, vendor
    }

    init(from decoder: Decoder) throws {
        let c   = try decoder.container(keyedBy: CodingKeys.self)
        id         = try  c.decode(String.self,  forKey: .id)
        number     = try? c.decode(String.self,  forKey: .number)
        status     = try? c.decode(String.self,  forKey: .status)
        dueDate    = try? c.decode(String.self,  forKey: .dueDate)
        total      = (try? c.decode(Double.self, forKey: .total))      ?? 0
        paidAmount = try? c.decode(Double.self,  forKey: .paidAmount)
        vendor     = try? c.decode(Vendor.self,  forKey: .vendor)
    }
}

// MARK: - View Model

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var invoices:  [Invoice]  = []
    @Published var quotes:    [Quote]    = []
    @Published var bills:     [DashBill] = []
    @Published var isLoading  = false
    @Published var range      = "YTD"
    private    var loaded     = false

    // ── Shared ISO parsers ───────────────────────────────────────────────────
    private let isoFull:  ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoShort: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private func parseDate(_ s: String) -> Date? { isoFull.date(from: s) ?? isoShort.date(from: s) }

    // ── Core financial metrics ───────────────────────────────────────────────
    var revenue: Double {
        invoices.filter { $0.status == "PAID" }.reduce(0) { $0 + $1.total }
    }
    var outstanding: Double {
        invoices.filter { $0.status == "SENT" }.reduce(0) { $0 + $1.total }
    }
    var overdue: Double {
        invoices.filter { $0.status == "OVERDUE" }.reduce(0) { $0 + $1.total }
    }
    var draft: Double {
        invoices.filter { $0.status == "DRAFT" }.reduce(0) { $0 + $1.total }
    }
    var outstandingCount: Int { invoices.filter { $0.status == "SENT"    }.count }
    var overdueCount:     Int { invoices.filter { $0.status == "OVERDUE" }.count }
    var draftCount:       Int { invoices.filter { $0.status == "DRAFT"   }.count }

    @Published var fiscalYearEndMonth: Int = 12
    @Published var expenses: Double = 0

    // ── Range-filtered revenue ───────────────────────────────────────────────
    var rangeRevenue: Double {
        let cal = Calendar.current
        let now = Date()
        let paid = invoices.filter { $0.status == "PAID" }
        switch range {
        case "MTD":
            let cm = cal.component(.month, from: now)
            let cy = cal.component(.year,  from: now)
            return paid.filter { inv in
                guard let d = parseDate(inv.createdAt) else { return false }
                return cal.component(.month, from: d) == cm
                    && cal.component(.year,  from: d) == cy
            }.reduce(0) { $0 + $1.total }
        case "QTD":
            let cq = (cal.component(.month, from: now) - 1) / 3
            let cy = cal.component(.year, from: now)
            return paid.filter { inv in
                guard let d = parseDate(inv.createdAt) else { return false }
                guard cal.component(.year, from: d) == cy else { return false }
                return (cal.component(.month, from: d) - 1) / 3 == cq
            }.reduce(0) { $0 + $1.total }
        default: // YTD, FY — all paid
            return revenue
        }
    }

    // ── Monthly bars for hero chart ──────────────────────────────────────────
    var monthlyData: [(label: String, value: Double, isCurrent: Bool)] {
        let cal = Calendar.current
        let now = Date()
        let df  = DateFormatter(); df.dateFormat = "MMM"
        let fyStartMonth = fiscalYearEndMonth % 12 + 1
        let currentMonth = cal.component(.month, from: now)
        let currentYear  = cal.component(.year,  from: now)
        var fyStartYear  = currentYear
        if currentMonth < fyStartMonth { fyStartYear -= 1 }
        let fyStart = cal.date(from: DateComponents(year: fyStartYear, month: fyStartMonth, day: 1))!

        return (0..<12).map { offset in
            let date  = cal.date(byAdding: .month, value: offset, to: fyStart)!
            let month = cal.component(.month, from: date)
            let year  = cal.component(.year,  from: date)
            let label = String(df.string(from: date).prefix(3))
            let val   = invoices.filter { $0.status == "PAID" }.compactMap { inv -> Double? in
                guard let d = parseDate(inv.createdAt) else { return nil }
                guard cal.component(.month, from: d) == month,
                      cal.component(.year,  from: d) == year  else { return nil }
                return inv.total
            }.reduce(0, +)
            let isCurrent = month == currentMonth && year == currentYear
            return (label, val, isCurrent)
        }
    }

    // ── Upcoming bills (due within 14 days, unpaid) ──────────────────────────
    var upcomingBills: [DashBill] {
        let now   = Date()
        let in14  = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        return bills
            .filter { b in
                guard let s = b.status, s != "PAID", let ds = b.dueDate,
                      let d = parseDate(ds) else { return false }
                return d >= now && d <= in14
            }
            .sorted { a, b in
                let da = a.dueDate.flatMap { parseDate($0) } ?? Date.distantFuture
                let db = b.dueDate.flatMap { parseDate($0) } ?? Date.distantFuture
                return da < db
            }
    }

    // ── Top customers from paid invoices ─────────────────────────────────────
    var topCustomers: [(name: String, initials: String, ltv: Double)] {
        var ltvMap:   [String: Double] = [:]
        var initMap:  [String: String] = [:]
        for inv in invoices where inv.status == "PAID" {
            let name: String
            let ini:  String
            if let c = inv.contact {
                name = c.displayName
                let f = c.firstName?.first.map(String.init) ?? ""
                let l = c.lastName?.first.map(String.init)  ?? ""
                ini  = (f + l).uppercased().isEmpty ? "?" : (f + l).uppercased()
            } else {
                name = inv.projectName ?? "Unknown"
                ini  = name.first.map { String($0).uppercased() } ?? "?"
            }
            ltvMap[name,  default: 0] += inv.total
            initMap[name] = ini
        }
        return ltvMap.sorted { $0.value > $1.value }
                     .prefix(3)
                     .map { (name: $0.key, initials: initMap[$0.key] ?? "?", ltv: $0.value) }
    }

    // ── Load ─────────────────────────────────────────────────────────────────
    func load() async {
        guard !loaded else { return }
        loaded    = true
        isLoading = true
        async let invTask:       [Invoice]          = (try? await APIService.shared.get("/invoices"))        ?? []
        async let qtTask:        [Quote]            = (try? await APIService.shared.get("/quotes"))          ?? []
        async let settingsTask:  CompanySettings?   =  try? await APIService.shared.get("/settings/company")
        async let purchasesTask: PurchasesSummary?  =  try? await APIService.shared.get("/purchases/summary")
        async let billsTask:     [DashBill]         = (try? await APIService.shared.get("/bills"))           ?? []
        let (i, q, s, p, b)  = await (invTask, qtTask, settingsTask, purchasesTask, billsTask)
        invoices  = i
        quotes    = q
        bills     = b
        expenses  = (p?.totalExpenses ?? 0) + (p?.paidBills ?? 0)
        if let endMonth = s?.settings?.fiscalYearEndMonth { fiscalYearEndMonth = endMonth }
        isLoading = false
    }

    func reload() async { loaded = false; await load() }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject var auth:     AuthService
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = DashboardViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                heroCard
                    .padding(.horizontal, 16)

                statusRow
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                upcomingBillsSection
                    .padding(.top, 12)

                modulesSection
                    .padding(.top, 12)

                topCustomersSection
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await vm.reload() }
        .task { await vm.load() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 38, height: 38)
                Text(auth.currentUser?.initials ?? "?")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(greeting.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(auth.currentUser?.displayName ?? "")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Notification bell
            Button { } label: {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 38, height: 38)
                    Image(systemName: "bell")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Hero Revenue Card

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            // Background gradient
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.10, green: 0.11, blue: 0.15), Color(red: 0.17, green: 0.19, blue: 0.26)]
                    : [Color(red: 0.059, green: 0.090, blue: 0.165), Color(red: 0.118, green: 0.176, blue: 0.294)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Orange glow (top right)
            Circle()
                .fill(Color.orange)
                .frame(width: 160, height: 160)
                .blur(radius: 50)
                .offset(x: 35, y: -50)
                .opacity(0.28)

            // Blue glow (bottom left)
            Circle()
                .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                .frame(width: 120, height: 120)
                .blur(radius: 60)
                .offset(x: -110, y: 55)
                .opacity(0.18)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Title + range tabs
                HStack(alignment: .center) {
                    Text("TOTAL REVENUE")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    rangeTabBar
                }
                .padding(.bottom, 14)

                // Big number + delta
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if vm.isLoading {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 180, height: 40)
                    } else {
                        Text(fmtShort(vm.rangeRevenue))
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    Text("+12.4%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }

                Text("vs. prior period")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 2)
                    .padding(.bottom, 18)

                miniBarChart
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Accent line at bottom
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.orange, .orange.opacity(0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }

    private var rangeTabBar: some View {
        HStack(spacing: 2) {
            ForEach(["MTD", "QTD", "YTD", "FY"], id: \.self) { key in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { vm.range = key }
                } label: {
                    Text(key)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(vm.range == key ? .black : .white.opacity(0.55))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            vm.range == key
                                ? Color.white.opacity(0.92)
                                : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
            }
        }
    }

    private var miniBarChart: some View {
        let data   = vm.monthlyData
        let maxVal = max(data.map(\.value).max() ?? 0, 1)

        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                let pct  = CGFloat(item.value / maxVal)
                let barH = item.value > 0 ? max(4, pct * 44) : CGFloat(3)
                let bg: Color = item.value == 0
                    ? .white.opacity(0.05)
                    : item.isCurrent ? .orange : .white.opacity(0.22)
                VStack(spacing: 4) {
                    Capsule()
                        .fill(bg)
                        .frame(height: barH)
                    Text(item.label)
                        .font(.system(size: 7.5, weight: item.isCurrent ? .bold : .regular))
                        .foregroundStyle(item.isCurrent ? Color.orange : .white.opacity(0.3))
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 60, alignment: .bottom)
    }

    // MARK: - Status row (Outstanding / Overdue / Draft)

    private var statusRow: some View {
        HStack(spacing: 8) {
            statusPill(label: "Outstanding", value: vm.outstanding, count: vm.outstandingCount, color: Color(red: 0.23, green: 0.51, blue: 0.96))
            statusPill(label: "Overdue",     value: vm.overdue,     count: vm.overdueCount,     color: Color(red: 0.94, green: 0.27, blue: 0.27))
            statusPill(label: "Draft",       value: vm.draft,       count: vm.draftCount,       color: Color(red: 0.96, green: 0.62, blue: 0.04))
        }
    }

    private func statusPill(label: String, value: Double, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(fmtShort(value))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Upcoming Bills (dark card)

    private var upcomingBillsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                // Background (same dark gradient as hero)
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.10, green: 0.11, blue: 0.15), Color(red: 0.17, green: 0.19, blue: 0.26)]
                        : [Color(red: 0.059, green: 0.090, blue: 0.165), Color(red: 0.118, green: 0.176, blue: 0.294)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("UPCOMING · BILLS")
                                .font(.system(size: 9.5, weight: .bold))
                                .tracking(1.5)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Text("PAY ALL →")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.orange)
                    }
                    .padding(.bottom, 14)

                    if vm.upcomingBills.isEmpty {
                        Text("No bills due in the next 14 days")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.vertical, 12)
                    } else {
                        ForEach(Array(vm.upcomingBills.prefix(3).enumerated()), id: \.element.id) { idx, bill in
                            if idx > 0 {
                                Divider().background(Color.white.opacity(0.08))
                            }
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bill.vendor?.name ?? "Unknown Vendor")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(fmtDue(bill.dueDate))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                Text(fmtShort(bill.total))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .padding(20)
            }
            // Accent line
            LinearGradient(
                colors: [.orange, .orange.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .padding(.horizontal, 16)
    }

    // MARK: - Workspace Modules

    private let moduleItems: [(label: String, icon: String)] = [
        ("Contacts",      "person.2.fill"),
        ("Open Tickets",  "ticket.fill"),
        ("Messages",      "message.fill"),
        ("Calls Logged",  "phone.fill"),
        ("Domains",       "network"),
        ("Users",         "person.badge.key.fill"),
    ]

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workspace")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(moduleItems.count) modules")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 20)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(moduleItems, id: \.label) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.orange)
                        Text(item.label)
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Top Customers

    private var topCustomersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TOP CUSTOMERS")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("CRM →")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.orange)
            }
            .padding(.bottom, 12)

            let customers = vm.topCustomers
            if customers.isEmpty {
                Text("No paid invoices yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(customers.enumerated()), id: \.element.name) { idx, c in
                    if idx > 0 {
                        Divider().padding(.leading, 52)
                    }
                    HStack(spacing: 12) {
                        // Rank
                        Text("\(idx + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Text(c.initials)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.orange)
                        }

                        Text(c.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(fmtShort(c.ltv))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 9)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func fmtShort(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "R%.1fM", v / 1_000_000) }
        if v >= 1_000     { return "R\(Int(v / 1_000))k" }
        return "R\(Int(v))"
    }

    private func fmtDue(_ ds: String?) -> String {
        guard let ds else { return "" }
        guard let d = isoFull.date(from: ds) ?? isoShort.date(from: ds) else { return "" }
        let cal  = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: Date()),
                                      to:   cal.startOfDay(for: d)).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days < 0  { return "Overdue" }
        return "In \(days) days"
    }

    private let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private let isoShort: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

// MARK: - Metric card (kept for other uses)

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
        if value >= 1_000_000 { return String(format: "R%.1fM", value / 1_000_000) }
        if value >= 1_000     { return "R\(Int(value / 1_000))k" }
        return value.formatted(.currency(code: "ZAR").presentation(.narrow))
    }
}

// MARK: - Transaction row (kept for other uses)

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
        let l = c.lastName?.first.map(String.init)  ?? ""
        let r = (f + l).uppercased()
        return r.isEmpty ? "?" : r
    }
    private var clientName: String { invoice.contact?.displayName ?? invoice.projectName ?? "No client" }
    private var statusColor: Color {
        switch invoice.status {
        case "SENT":      return Color(red: 0, green: 0.478, blue: 1)
        case "PAID":      return .green
        case "OVERDUE":   return Color(red: 1, green: 0.231, blue: 0.188)
        case "CANCELLED": return Color(.systemGray3)
        default:          return Color(.systemGray)
        }
    }
}

// MARK: - Avatar (kept for other files)

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
