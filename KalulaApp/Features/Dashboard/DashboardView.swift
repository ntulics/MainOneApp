import SwiftUI

// MARK: - Donut segment filled shape
// Draws a proper donut arc as a filled path (not a stroked circle).
// This lets SwiftUI's shadow behave like a physical slab — visible only
// at exposed edges, hidden where the next overlapping segment covers it.
private struct DonutSegment: Shape {
    let startFraction: Double   // 0…1 of full circle
    let endFraction:   Double
    let innerRatio:    CGFloat  // inner radius as fraction of view half-width
    let outerRatio:    CGFloat  // outer radius as fraction of view half-width

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let r  = min(rect.width, rect.height) / 2
        let ri = r * innerRatio
        let ro = r * outerRatio
        let s  = Angle(degrees: startFraction * 360 - 90)
        let e  = Angle(degrees: endFraction   * 360 - 90)
        var p  = Path()
        p.addArc(center: CGPoint(x: cx, y: cy), radius: ro,
                 startAngle: s, endAngle: e, clockwise: false)
        p.addArc(center: CGPoint(x: cx, y: cy), radius: ri,
                 startAngle: e, endAngle: s, clockwise: true)
        p.closeSubpath()
        return p
    }
}

private struct DonutEndShadow: View {
    let fraction: Double
    let innerRatio: CGFloat
    let outerRatio: CGFloat
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            let ringMid = radius * (innerRatio + outerRatio) / 2
            let ringThickness = radius * (outerRatio - innerRatio)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let angle = (fraction * 360 - 90) * .pi / 180
            let directionX = CGFloat(cos(angle))
            let directionY = CGFloat(sin(angle))

            Capsule()
                .fill(.black.opacity(opacity))
                .frame(width: max(4, ringThickness * 0.16), height: ringThickness * 0.92)
                .blur(radius: 3)
                .rotationEffect(.degrees(fraction * 360))
                .position(
                    x: center.x + directionX * ringMid,
                    y: center.y + directionY * ringMid
                )
        }
        .allowsHitTesting(false)
    }
}

private struct DonutSliceLabel: View {
    let percent: Int
    let isCompact: Bool

    var body: some View {
        Text("\(percent)%")
            .font(.system(size: isCompact ? 11 : 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Private models

private struct PurchasesSummary: Decodable {
    let totalExpenses: Double
    let paidBills:     Double
}

private struct RecurringExpenseItem: Decodable, Identifiable {
    let id:               String
    let description:      String?
    let total:            Double
    let nextExpenseDate:  String?
    let isActive:         Bool?
    let frequency:        String?
    let vendor:           VendorRef?
    struct VendorRef: Decodable { let name: String? }

    private enum CodingKeys: String, CodingKey {
        case id, description, total, nextExpenseDate, isActive, frequency, vendor
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try  c.decode(String.self, forKey: .id)
        description     = try? c.decode(String.self, forKey: .description)
        total           = (try? c.decode(Double.self, forKey: .total)) ?? 0
        nextExpenseDate = try? c.decode(String.self, forKey: .nextExpenseDate)
        isActive        = try? c.decode(Bool.self,   forKey: .isActive)
        frequency       = try? c.decode(String.self, forKey: .frequency)
        vendor          = try? c.decode(VendorRef.self, forKey: .vendor)
    }
}

// Unified upcoming expense item (bills + recurring expenses)
private struct UpcomingExpenseEntry: Identifiable {
    let id:     String
    let name:   String
    let amount: Double
    let dueDate: Date?
    let badge:  String   // "BILL" | "MONTHLY" | "WEEKLY" | "ANNUAL" etc.
}

private struct DashBill: Decodable, Identifiable {
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

// MARK: - Module counts models

private struct DashboardSummary: Decodable {
    struct Stats: Decodable {
        let contacts:    Int?
        let openTickets: Int?
        let messages:    Int?
        let calls:       Int?
    }
    let stats: Stats?
}

private struct DomainsListResponse: Decodable {
    struct DomainItem: Decodable {
        let id: String
        let domainName: String?
        let expiryDate: String?
        let tld: String?          // e.g. "co.za", "com" — used for renewal price lookup
    }
    let domains: [DomainItem]?
}

private struct UserListItem: Decodable { let id: String }

// Estimated renewal price by TLD (ZAR). Used when no live price is available.
private func tldRenewalPrice(_ tld: String) -> Double? {
    let t = tld.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    switch t {
    case "co.za", "org.za", "net.za", "web.za", "edu.za": return 120
    case "com", "net", "org", "info", "biz":               return 350
    case "io":                                             return 650
    case "co", "app", "dev":                               return 450
    case "store", "shop":                                  return 350
    case "online", "site":                                 return 300
    case "africa":                                         return 250
    case "joburg", "capetown", "durban":                   return 200
    default:                                               return nil
    }
}

private struct DomainRenewal: Identifiable {
    let id: String
    let name: String
    let expiryDate: Date?
    let renewalPrice: Double?     // nil if TLD not in lookup table

    var daysLeft: Int? {
        guard let d = expiryDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: Date()),
                                  to:   cal.startOfDay(for: d)).day
    }

    var urgencyColor: Color {
        guard let days = daysLeft else { return .secondary }
        if days <= 14 { return Color(red: 0.94, green: 0.27, blue: 0.27) }
        if days <= 60 { return Color(red: 0.95, green: 0.62, blue: 0.04) }
        return Color(red: 0.13, green: 0.70, blue: 0.35)
    }
}

// Individual expense record (PENDING / OVERDUE = unpaid)
private struct ExpenseItem: Decodable, Identifiable {
    let id:          String
    let status:      String?
    let total:       Double
    let description: String?
    let date:        String?
    let vendor:      VendorRef?
    struct VendorRef: Decodable { let name: String? }

    private enum CodingKeys: String, CodingKey {
        case id, status, total, description, date, vendor
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try  c.decode(String.self, forKey: .id)
        status      = try? c.decode(String.self, forKey: .status)
        total       = (try? c.decode(Double.self, forKey: .total)) ?? 0
        description = try? c.decode(String.self, forKey: .description)
        date        = try? c.decode(String.self, forKey: .date)
        vendor      = try? c.decode(VendorRef.self, forKey: .vendor)
    }
}

// MARK: - View Model

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var invoices:  [Invoice]  = []
    @Published var quotes:    [Quote]    = []
    @Published fileprivate var bills:              [DashBill]             = []
    @Published fileprivate var recurringExpenses:  [RecurringExpenseItem] = []
    @Published fileprivate var expenseItems:       [ExpenseItem]          = []
    @Published var isLoading  = false
    @Published var range      = "YTD"
    private    var loaded     = false

    // ── Workspace module counts ──────────────────────────────────────────────
    @Published var contactCount: Int = 0
    @Published var ticketCount:  Int = 0
    @Published var messageCount: Int = 0
    @Published var callCount:    Int = 0
    @Published var domainCount:  Int = 0
    @Published fileprivate var domainItems:  [DomainRenewal] = []
    @Published var userCount:    Int = 0

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
    // Note: split filter and reduce into two lines each to help SourceKit type-check.
    var revenue: Double {
        let paid = invoices.filter { $0.status == "PAID" }
        return paid.reduce(0) { $0 + $1.total }
    }
    var outstanding: Double {
        let sent = invoices.filter { $0.status == "SENT" }
        return sent.reduce(0) { $0 + $1.total }
    }
    var overdue: Double {
        let od = invoices.filter { $0.status == "OVERDUE" }
        return od.reduce(0) { $0 + $1.total }
    }
    var draft: Double {
        let dr = invoices.filter { $0.status == "DRAFT" }
        return dr.reduce(0) { $0 + $1.total }
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
    // NOTE: complex closures inside .map broke SourceKit's type-checker.
    // Extracted the paid-invoice filter and bar-value helper to keep each
    // expression simple enough for the compiler to check quickly.
    var monthlyData: [(label: String, value: Double, isCurrent: Bool)] {
        let cal          = Calendar.current
        let now          = Date()
        let df           = DateFormatter(); df.dateFormat = "MMM"
        let fyStartMonth = fiscalYearEndMonth % 12 + 1
        let currentMonth = cal.component(.month, from: now)
        let currentYear  = cal.component(.year,  from: now)
        var fyStartYear  = currentYear
        if currentMonth < fyStartMonth { fyStartYear -= 1 }
        let fyStart      = cal.date(from: DateComponents(year: fyStartYear, month: fyStartMonth, day: 1))!
        let paidInvoices = invoices.filter { $0.status == "PAID" }

        return (0..<12).map { offset -> (label: String, value: Double, isCurrent: Bool) in
            let date      = cal.date(byAdding: .month, value: offset, to: fyStart)!
            let month     = cal.component(.month, from: date)
            let year      = cal.component(.year,  from: date)
            let label     = String(df.string(from: date).prefix(3))
            let isCurrent = month == currentMonth && year == currentYear
            let val: Double = paidInvoices.reduce(0) { sum, inv in
                // Use paidAt when present so backdated payments land in the right month
                guard let d = parseDate(inv.paidAt ?? inv.createdAt) else { return sum }
                let m = cal.component(.month, from: d)
                let y = cal.component(.year,  from: d)
                return (m == month && y == year) ? sum + inv.total : sum
            }
            return (label, val, isCurrent)
        }
    }

    // ── Upcoming expenses: unpaid bills due in 30 days + active recurring ──────
    fileprivate var upcomingExpenses: [UpcomingExpenseEntry] {
        let cal   = Calendar.current
        let now   = Date()
        let in30  = cal.date(byAdding: .day, value: 30, to: now) ?? now

        var entries: [UpcomingExpenseEntry] = []

        // 1. Bills due within 30 days, unpaid
        for b in bills {
            guard let s = b.status, s != "PAID" else { continue }
            guard let ds = b.dueDate, let d = parseDate(ds) else { continue }
            guard d >= now && d <= in30 else { continue }
            let name = b.vendor?.name ?? b.number ?? "Bill"
            entries.append(UpcomingExpenseEntry(id: "bill-\(b.id)", name: name,
                                                amount: b.total, dueDate: d, badge: "BILL"))
        }

        // 2. Active recurring expenses (show all active; sort by next due date)
        for r in recurringExpenses {
            guard r.isActive == true else { continue }
            let dueDate = r.nextExpenseDate.flatMap { parseDate($0) }
            let name    = r.vendor?.name ?? r.description ?? "Recurring"
            let badge   = r.frequency.map { $0.capitalized } ?? "Recurring"
            entries.append(UpcomingExpenseEntry(id: "rec-\(r.id)", name: name,
                                                amount: r.total, dueDate: dueDate, badge: badge))
        }

        // 3. Unpaid / overdue individual expense records
        for e in expenseItems {
            guard let s = e.status, s != "PAID" else { continue }
            let dueDate = e.date.flatMap { parseDate($0) }
            let name    = e.vendor?.name ?? e.description ?? "Expense"
            let badge   = s == "OVERDUE" ? "OVERDUE" : "UNPAID"
            entries.append(UpcomingExpenseEntry(id: "exp-\(e.id)", name: name,
                                                amount: e.total, dueDate: dueDate, badge: badge))
        }

        // 4. Domains expiring within 90 days or already expired (where TLD price is known)
        for domain in domainItems {
            guard let price = domain.renewalPrice else { continue }
            guard let daysLeft = domain.daysLeft, daysLeft <= 90 else { continue }
            let badge = daysLeft <= 0 ? "EXPIRED" : "DOMAIN"
            entries.append(UpcomingExpenseEntry(id: "dom-\(domain.id)", name: domain.name,
                                                amount: price, dueDate: domain.expiryDate, badge: badge))
        }

        return entries.sorted { a, b in
            let da = a.dueDate ?? Date.distantFuture
            let db = b.dueDate ?? Date.distantFuture
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

    // ── Top expenses by amount ───────────────────────────────────────────────
    var topExpenses: [(id: String, name: String, amount: Double, date: Date?)] {
        expenseItems
            .sorted { $0.total > $1.total }
            .prefix(5)
            .map { e in
                let name = e.vendor?.name ?? e.description ?? "Expense"
                let date = e.date.flatMap { parseDate($0) }
                return (id: e.id, name: name, amount: e.total, date: date)
            }
    }

    var upcomingExpenseCount: Int { upcomingExpenses.count }
    var upcomingExpenseTotal: Double { upcomingExpenses.reduce(0) { $0 + $1.amount } }

    // ── Load ─────────────────────────────────────────────────────────────────
    func load() async {
        guard !loaded else { return }
        loaded    = true
        isLoading = true
        async let invTask:       [Invoice]              = (try? await APIService.shared.get("/invoices"))           ?? []
        async let qtTask:        [Quote]                = (try? await APIService.shared.get("/quotes"))             ?? []
        async let settingsTask:  CompanySettings?       =  try? await APIService.shared.get("/settings/company")
        async let purchasesTask: PurchasesSummary?      =  try? await APIService.shared.get("/purchases/summary")
        async let billsTask:     [DashBill]             = (try? await APIService.shared.get("/bills"))              ?? []
        async let recurringTask: [RecurringExpenseItem] = (try? await APIService.shared.get("/recurring-expenses")) ?? []
        async let expTask:       [ExpenseItem]          = (try? await APIService.shared.get("/expenses"))           ?? []
        async let summaryTask:   DashboardSummary?      =  try? await APIService.shared.get("/dashboard/summary")
        async let domainsTask:   DomainsListResponse?   =  try? await APIService.shared.get("/domains")
        async let usersTask:     [UserListItem]         = (try? await APIService.shared.get("/identity/users"))    ?? []

        let (i, q, s, p, b, rec, exp, sum, dom, usr) = await (invTask, qtTask, settingsTask, purchasesTask, billsTask, recurringTask, expTask, summaryTask, domainsTask, usersTask)
        invoices           = i
        quotes             = q
        bills              = b
        recurringExpenses  = rec
        expenseItems       = exp
        expenses  = (p?.totalExpenses ?? 0) + (p?.paidBills ?? 0)
        if let endMonth = s?.settings?.fiscalYearEndMonth { fiscalYearEndMonth = endMonth }
        contactCount = sum?.stats?.contacts    ?? 0
        ticketCount  = sum?.stats?.openTickets ?? 0
        messageCount = sum?.stats?.messages    ?? 0
        callCount    = sum?.stats?.calls       ?? 0
        domainCount  = dom?.domains?.count ?? 0
        domainItems  = (dom?.domains ?? []).map { item in
            DomainRenewal(id: item.id,
                          name: item.domainName ?? item.id,
                          expiryDate: item.expiryDate.flatMap { parseDate($0) },
                          renewalPrice: item.tld.flatMap { tldRenewalPrice($0) })
        }
        userCount    = usr.count
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

                swipeableHeroCards
                    .padding(.top, 4)

                statusRow
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                topExpensesSection
                    .padding(.top, 12)

                topCustomersSection
                    .padding(.top, 12)

                domainRenewalsSection
                    .padding(.top, 12)

                modulesSection
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

            HStack(spacing: 10) {
                // Notification bell
                Button { } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 38, height: 38)
                        Image(systemName: "bell")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }

                // App launcher
                Button { appState.showMore = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 38, height: 38)
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    // MARK: - Swipeable hero carousel (Revenue · Financial Overview · Cash Flow)

    private var swipeableHeroCards: some View {
        TabView {
            financialOverviewCard.tag(0)
            revenueCard.tag(1)
            cashFlowCard.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .padding(.horizontal, 16)
    }

    // MARK: - Adaptive card colours (light ↔ dark)

    private var cardGradientColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.10, green: 0.11, blue: 0.15), Color(red: 0.17, green: 0.19, blue: 0.26)]
            : [Color(.systemBackground), Color(.secondarySystemBackground)]
    }
    private var cardLabelColor:  Color { colorScheme == .dark ? .white.opacity(0.50) : Color(.secondaryLabel) }
    private var cardValueColor:  Color { colorScheme == .dark ? .white               : Color(.label) }
    private var cardSubtleColor: Color { colorScheme == .dark ? .white.opacity(0.35) : Color(.tertiaryLabel) }
    private var cardBarRest:     Color { colorScheme == .dark ? .white.opacity(0.22) : .black.opacity(0.10) }
    private var cardBarZero:     Color { colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.04) }
    private var cardBarLabel:    Color { colorScheme == .dark ? .white.opacity(0.30) : Color(.tertiaryLabel) }
    private var cardDivider:     Color { colorScheme == .dark ? .white.opacity(0.08) : Color(.separator).opacity(0.5) }
    private var cardHoleColor:   Color {
        colorScheme == .dark
            ? Color(red: 0.059, green: 0.090, blue: 0.165)
            : Color(.systemBackground)
    }
    private var rangeTabActiveBg:   Color { colorScheme == .dark ? .white.opacity(0.92) : Color(.label).opacity(0.10) }
    private var rangeTabActiveText: Color { colorScheme == .dark ? .black               : Color(.label) }
    private var rangeTabInactiveBg: Color { colorScheme == .dark ? .white.opacity(0.08) : .clear }
    private var rangeTabInactiveText: Color { colorScheme == .dark ? .white.opacity(0.55) : Color(.secondaryLabel) }

    // Shared card shell — gradient + ambient glows + bottom accent line
    @ViewBuilder
    private func darkCardShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: cardGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.orange).frame(width: 160, height: 160).blur(radius: 50).offset(x: 40, y: -55)
                .opacity(colorScheme == .dark ? 0.26 : 0.18)
            Circle().fill(Color(red: 0.0, green: 0.48, blue: 1.0)).frame(width: 120, height: 120).blur(radius: 60).offset(x: -110, y: 60)
                .opacity(colorScheme == .dark ? 0.16 : 0.10)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack {
                Spacer()
                LinearGradient(colors: [.orange, .orange.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)
            }
        }
    }

    // ── Card 1: Total Revenue ─────────────────────────────────────────────────

    private var revenueCard: some View {
        darkCardShell {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("TOTAL REVENUE")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(cardLabelColor)
                    Spacer()
                    rangeTabBar
                }
                .padding(.bottom, 14)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if vm.isLoading {
                        RoundedRectangle(cornerRadius: 8).fill(cardBarZero).frame(width: 180, height: 40)
                    } else {
                        Text(fmtShort(vm.rangeRevenue))
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(cardValueColor)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    Text("+12.4%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }

                Text("vs. prior period")
                    .font(.system(size: 11))
                    .foregroundStyle(cardSubtleColor)
                    .padding(.top, 2)

                Spacer(minLength: 0)

                miniBarChart
            }
            .padding(20)
            .frame(maxHeight: .infinity)
        }
    }

    // ── Card 2: Financial Overview ────────────────────────────────────────────

    private var financialOverviewCard: some View {
        let rev      = vm.revenue
        let exp      = vm.expenses
        let net      = rev - exp
        let pl       = abs(net)
        let isProfit = net >= 0
        let plColor  = isProfit ? Color(red: 0.06, green: 0.73, blue: 0.51) : Color(red: 0.94, green: 0.27, blue: 0.27)
        let colors:  [Color]  = [Color.orange, Color(red: 0.56, green: 0.56, blue: 0.58), plColor]
        let labels:  [String] = ["Revenue", "Expenses", isProfit ? "Profit" : "Loss"]
        let values:  [Double] = [rev, exp, pl]
        let total   = rev + exp + pl
        let hasSeg  = total > 0
        let fracs   = hasSeg ? [rev/total, exp/total, pl/total] : [1.0/3, 1.0/3, 1.0/3]
        let percents = fracs.map { Int(round($0 * 100)) }
        let outerRatios: [CGFloat] = [0.98, 1.03, 1.01]
        var boundaries = [0.0]
        for f in fracs { boundaries.append(min(boundaries.last! + f, 1.0)) }
        let st = (0..<3).map { boundaries[$0] }
        let en = (0..<3).map { boundaries[$0 + 1] }

        return darkCardShell {
            VStack(alignment: .leading, spacing: 0) {
                Text("FINANCIAL OVERVIEW")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(cardLabelColor)
                    .padding(.bottom, 6)

                // Donut + legend — sized to content, sits tight under label
                HStack(alignment: .center, spacing: 16) {
                    GeometryReader { proxy in
                        let size = min(proxy.size.width, proxy.size.height)
                        let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        let labelRadius = size * 0.39

                        ZStack {
                            ForEach(0..<3, id: \.self) { k in
                                let mid = (st[k] + en[k]) / 2
                                let angle = (mid * 360 - 90) * .pi / 180
                                let directionX = CGFloat(cos(angle))
                                let directionY = CGFloat(sin(angle))
                                let labelPoint = CGPoint(
                                    x: center.x + directionX * labelRadius,
                                    y: center.y + directionY * labelRadius
                                )
                                DonutSegment(
                                    startFraction: st[k],
                                    endFraction: max(st[k], en[k]),
                                    innerRatio: 0.48,
                                    outerRatio: outerRatios[k]
                                )
                                .fill(colors[k])
                                .shadow(color: .black.opacity(0.42), radius: 9, x: 0, y: 6)

                                DonutEndShadow(
                                    fraction: en[k],
                                    innerRatio: 0.48,
                                    outerRatio: outerRatios[k],
                                    opacity: k == 1 ? 0.34 : 0.24
                                )

                                DonutSliceLabel(
                                    percent: percents[k],
                                    isCompact: fracs[k] < 0.12
                                )
                                .frame(width: 58, height: 34)
                                .position(labelPoint)
                            }

                            Circle()
                                .fill(cardHoleColor)
                                .frame(width: size * 0.50, height: size * 0.50)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.78 : 0.34),
                                        radius: 14, x: 0, y: 8)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.14),
                                        radius: 4, x: 0, y: 2)
                            VStack(spacing: 3) {
                                Text("NET")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(cardLabelColor)
                                    .tracking(0.5)
                                Text(fmtShort(pl))
                                    .font(.system(size: 17, weight: .black, design: .rounded))
                                    .foregroundStyle(plColor)
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Text(isProfit ? "profit" : "loss")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(cardSubtleColor)
                            }
                        }
                    }
                    .frame(width: 204, height: 204)
                    .offset(y: 2)

                    // Legend
                    let iconNames = ["icon-revenue-wallet", "icon-expenses-arrow", isProfit ? "icon-profit-up" : "icon-profit-down"]
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(0..<3, id: \.self) { k in
                            HStack(alignment: .center, spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(colors[k]).frame(width: 3, height: 36)
                                Image(iconNames[k])
                                    .resizable()
                                    .renderingMode(.template)
                                    .foregroundStyle(colors[k])
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(labels[k])
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(cardLabelColor)
                                        .textCase(.uppercase)
                                    Text(fmtShort(values[k]))
                                        .font(.system(size: 17, weight: .black, design: .rounded))
                                        .foregroundStyle(cardValueColor)
                                        .minimumScaleFactor(0.65)
                                        .lineLimit(1)
                                    Text("\(percents[k])% of total")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(cardSubtleColor)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Absorb leftover vertical space below the donut
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxHeight: .infinity)
        }
    }

    // ── Card 3: Cash Flow ─────────────────────────────────────────────────────

    private var cashFlowCard: some View {
        let data     = vm.monthlyData
        let maxVal   = max(data.map(\.value).max() ?? 0, 1)
        let net      = vm.revenue - vm.expenses
        let isProfit = net >= 0
        let netColor = isProfit ? Color(red: 0.06, green: 0.73, blue: 0.51) : Color(red: 0.94, green: 0.27, blue: 0.27)

        return darkCardShell {
            VStack(alignment: .leading, spacing: 0) {
                Text("CASH FLOW · FY")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(cardLabelColor)
                    .padding(.bottom, 12)

                // Stats row
                HStack(spacing: 0) {
                    ForEach([
                        (label: "Money In",  value: vm.revenue,   color: Color.orange),
                        (label: "Money Out", value: vm.expenses,  color: cardSubtleColor),
                        (label: "Net",       value: abs(net),     color: netColor),
                    ], id: \.label) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.label)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(cardLabelColor)
                            Text(fmtShort(stat.value))
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(stat.color)
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer(minLength: 0)

                // Monthly bars (revenue = "money in" trend)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                        miniBar(item: item, maxVal: maxVal, maxH: 38, tint: Color(red: 0.06, green: 0.73, blue: 0.51))
                    }
                }
                .frame(height: 52, alignment: .bottom)
            }
            .padding(20)
            .frame(maxHeight: .infinity)
        }
    }

    private var rangeTabBar: some View {
        HStack(spacing: 2) {
            ForEach(["MTD", "QTD", "YTD", "FY"], id: \.self) { key in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { vm.range = key }
                } label: {
                    Text(key)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(vm.range == key ? rangeTabActiveText : rangeTabInactiveText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            vm.range == key ? rangeTabActiveBg : rangeTabInactiveBg,
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
            ForEach(Array(data.enumerated()), id: \.offset) { idx, item in
                miniBar(item: item, maxVal: maxVal, maxH: 44, tint: .orange)
            }
        }
        .frame(height: 60, alignment: .bottom)
    }

    // Extracted so the type-checker doesn't time out inside ForEach
    private func miniBar(item: (label: String, value: Double, isCurrent: Bool),
                         maxVal: Double, maxH: CGFloat, tint: Color) -> some View {
        let pct:  CGFloat = item.value > 0 ? CGFloat(item.value / maxVal) : 0
        let barH: CGFloat = item.value > 0 ? max(3, pct * maxH) : 2
        let bg: Color     = item.value == 0 ? cardBarZero : (item.isCurrent ? tint : cardBarRest)
        return VStack(spacing: 4) {
            Capsule().fill(bg).frame(height: barH)
            Text(item.label)
                .font(.system(size: 7.5, weight: item.isCurrent ? .bold : .regular))
                .foregroundStyle(item.isCurrent ? tint : cardBarLabel)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    // MARK: - Status row (Outstanding / Overdue / Draft)

    private var statusRow: some View {
        HStack(spacing: 8) {
            statusPill(label: "Outstanding", value: vm.outstanding, count: vm.outstandingCount, color: Color(red: 0.23, green: 0.51, blue: 0.96))
            statusPill(label: "Overdue",     value: vm.overdue,     count: vm.overdueCount,     color: Color(red: 0.94, green: 0.27, blue: 0.27))
            statusPill(label: "Upcoming",    value: vm.upcomingExpenseTotal, count: vm.upcomingExpenseCount, color: Color(red: 0.96, green: 0.62, blue: 0.04))
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

    // MARK: - Top Expenses

    private var topExpensesSection: some View {
        let items = vm.topExpenses
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: cardGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("TOP · EXPENSES")
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(cardLabelColor)
                        Spacer()
                        Text("VIEW ALL →")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.orange)
                    }
                    .padding(.bottom, 14)

                    if items.isEmpty {
                        Text("No expenses recorded")
                            .font(.system(size: 13))
                            .foregroundStyle(cardSubtleColor)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 { Divider().overlay(cardDivider) }
                            HStack(spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(cardSubtleColor)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(cardValueColor)
                                        .lineLimit(1)
                                    if let d = item.date {
                                        Text(d, format: .dateTime.day().month(.abbreviated).year())
                                            .font(.system(size: 10))
                                            .foregroundStyle(cardSubtleColor)
                                    }
                                }
                                Spacer()
                                Text(fmtShort(item.amount))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(cardValueColor)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .padding(20)
            }
            LinearGradient(colors: [.orange, .orange.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .padding(.horizontal, 16)
    }

    // financialOverviewCard and cashFlowCard are now inside swipeableHeroCards (TabView pager)

    // MARK: - Domain Renewals

    private var domainRenewalsSection: some View {
        Group {
            if !vm.domainItems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        LinearGradient(colors: cardGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)

                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("DOMAIN RENEWALS")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundStyle(cardLabelColor)
                                Spacer()
                                Text("MANAGE →")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(Color.orange)
                            }
                            .padding(.bottom, 14)

                            ForEach(Array(vm.domainItems.enumerated()), id: \.element.id) { idx, domain in
                                if idx > 0 {
                                    Divider().overlay(cardDivider)
                                }
                                HStack(spacing: 12) {
                                    Image(systemName: "network")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.orange)
                                        .frame(width: 30, height: 30)
                                        .background(Color.orange.opacity(0.14),
                                                    in: RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(domain.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(cardValueColor)
                                            .lineLimit(1)
                                        if let expiry = domain.expiryDate {
                                            Text("Renews \(expiry, style: .date)")
                                                .font(.system(size: 10))
                                                .foregroundStyle(cardSubtleColor)
                                        } else {
                                            Text("Annual renewal")
                                                .font(.system(size: 10))
                                                .foregroundStyle(cardSubtleColor)
                                        }
                                    }
                                    Spacer()
                                    if let days = domain.daysLeft {
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text(days <= 0 ? "EXPIRED" : "\(days)d")
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .foregroundStyle(domain.urgencyColor)
                                            Text(days <= 0 ? "" : "left")
                                                .font(.system(size: 8, weight: .medium))
                                                .foregroundStyle(cardSubtleColor)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(domain.urgencyColor.opacity(0.18), in: Capsule())
                                    }
                                }
                                .padding(.vertical, 10)
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
        }
    }

    // MARK: - Workspace Modules

    private var modulesSection: some View {
        let items: [(label: String, icon: String, count: Int)] = [
            ("Contacts",     "person.2.fill",          vm.contactCount),
            ("Open Tickets", "ticket.fill",             vm.ticketCount),
            ("Messages",     "message.fill",            vm.messageCount),
            ("Calls Logged", "phone.fill",              vm.callCount),
            ("Domains",      "network",                 vm.domainCount),
            ("Users",        "person.badge.key.fill",   vm.userCount),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workspace")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(items.count) modules")
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
                ForEach(items, id: \.label) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.orange)
                            Spacer()
                        }
                        Text(vm.isLoading ? "—" : "\(item.count)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(item.label)
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.4)
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

    private func fmtDueDate(_ d: Date) -> String {
        let cal  = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                              to:   cal.startOfDay(for: d)).day ?? 0
        if days < 0  { return "Overdue" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days <= 7 { return "In \(days) days" }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

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
