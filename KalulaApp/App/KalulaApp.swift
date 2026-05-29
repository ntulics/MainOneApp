import SwiftUI

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var showScanner  = false
    @Published var scannerType: DocumentType = .vendorQuote
    @Published var showMore     = false
}

// MARK: - Entry point

@main
struct KalulaApp: App {
    @StateObject private var auth     = AuthService.shared
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(appState)
                .task { await auth.restoreSession() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        Group {
            if auth.isBiometricLocked {
                BiometricLockView()
            } else if auth.isAuthenticated {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    iPadMainView()
                } else {
                    MainTabView()
                }
            } else {
                LoginRootView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isBiometricLocked)
        .animation(.easeInOut(duration: 0.25), value: auth.isAuthenticated)
    }
}

// MARK: - Main tab view

struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            TabView {
                DashboardView()
                    .tabItem { Label("Dashboard", systemImage: "house.fill") }

                CustomersView()
                    .tabItem { Label("Customers", systemImage: "person.2.fill") }

                SalesView()
                    .tabItem { Label("Sales", systemImage: "doc.text.fill") }

                PurchasesView()
                    .tabItem { Label("Purchases", systemImage: "cart.fill") }

                MoreTabView()
                    .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
            }
            .tint(.brand)
        }
        .fullScreenCover(isPresented: $appState.showScanner) {
            ScannerView(initialType: appState.scannerType)
        }
    }
}

// MARK: - More tab (Documents + Settings)

struct MoreTabView: View {
    @EnvironmentObject var auth:     AuthService
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Business ───────────────────────────────────────────
                    MenuSection(title: "Business") {
                        HStack(spacing: 12) {
                            NavigationLink(destination: SuppliersView()) {
                                MenuTileContent(title: "Suppliers", icon: "shippingbox.fill", color: .green)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Spacer()
                        }
                    }

                    // ── Documents ──────────────────────────────────────────
                    MenuSection(title: "Documents") {
                        HStack(spacing: 12) {
                            NavigationLink(destination: DocumentsView(initialType: nil)) {
                                MenuTileContent(title: "All Documents", icon: "folder.fill", color: .indigo)
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: ImportantDocumentsView()) {
                                MenuTileContent(title: "Important", icon: "star.fill", color: .yellow)
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                    }

                    // ── Settings ───────────────────────────────────────────
                    MenuSection(title: "Settings") {
                        HStack(spacing: 12) {
                            NavigationLink(destination: TenantSettingsView()) {
                                MenuTileContent(title: "Company", icon: "building.2.fill", color: .blue)
                            }
                            .buttonStyle(.plain)
                            NavigationLink(destination: PreferencesView()) {
                                MenuTileContent(title: "Preferences", icon: "gearshape.fill", color: Color.brand)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                    }
                }
                .padding()
                .padding(.bottom, 8)
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)

            // Sign out at bottom
            Divider()
            Button(role: .destructive) {
                auth.logout()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .foregroundStyle(.red)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, max(28, 16))
        }
    }
}

private struct MenuTileContent: View {
    let title: String
    let icon:  String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 52, height: 52)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Document type tile (view + optional scan)

private struct DocTypeTile: View {
    let title:   String
    let icon:    String
    let color:   Color
    let canScan: Bool
    let onView:  () -> Void
    let onScan:  () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onView) {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                        .frame(width: 52, height: 52)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            if canScan {
                Button(action: onScan) {
                    Label("Scan", systemImage: "camera.viewfinder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(height: 22)
            }
        }
    }
}

// MARK: - Menu sub-components

struct MenuSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(1)
            content()
        }
    }
}

// MARK: - Preferences view

struct PreferencesView: View {
    @State private var quoteFormat        = DocumentNumberFormat(prefix: "QUO", separator: "", dateFormat: "YYMM", seqDigits: 3)
    @State private var invoiceFormat      = DocumentNumberFormat(prefix: "INV", separator: "", dateFormat: "YYMM", seqDigits: 3)
    @State private var fiscalYearEndMonth = 12   // preserve when saving numbering
    @State private var isLoading = true
    @State private var saving    = false
    @State private var saved     = false
    @State private var error     = ""

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        NumberFormatSection(format: $quoteFormat)
                    } header: { Text("Quote Numbering") }

                    Section {
                        NumberFormatSection(format: $invoiceFormat)
                    } header: { Text("Invoice Numbering") }

                    if saved {
                        Section {
                            Label("Preferences saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline.bold())
                        }
                    }
                    if !error.isEmpty {
                        Section { Text(error).foregroundStyle(.red).font(.caption) }
                    }
                }
            }
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await save() } } label: {
                    if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                }
                .disabled(saving || isLoading)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        if let s: CompanySettings = try? await APIService.shared.get("/settings/company") {
            if let qf  = s.settings?.quoteNumberFormat   { quoteFormat   = qf }
            if let inf = s.settings?.invoiceNumberFormat { invoiceFormat = inf }
            fiscalYearEndMonth = s.settings?.fiscalYearEndMonth ?? 12
        }
        isLoading = false
    }

    private func save() async {
        saving = true; error = ""; saved = false
        do {
            let body = UpdateCompanySettings(
                name: nil, contactEmail: nil, contactPhone: nil,
                address: nil, taxRate: nil, currency: nil,
                settings: CompanyDocumentSettings(
                    quoteNumberFormat:   quoteFormat,
                    invoiceNumberFormat: invoiceFormat,
                    fiscalYearEndMonth:  fiscalYearEndMonth
                )
            )
            let _: CompanySettings = try await APIService.shared.patch("/settings/company", body: body)
            saved = true
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}

struct NumberFormatSection: View {
    @Binding var format: DocumentNumberFormat

    private let separators  = [("", "None"), ("-", "Dash (-)"), ("/", "Slash (/)" ), (".", "Dot (.)")]
    private let dateFormats = [
        ("YYMM",   "YYMM — e.g. 2605"),
        ("YYYY",   "YYYY — e.g. 2026"),
        ("YYYYMM", "YYYYMM — e.g. 202605"),
        ("YY",     "YY — e.g. 26"),
        ("MM",     "MM — e.g. 05"),
        ("NONE",   "None (no date)"),
    ]

    var body: some View {
        HStack {
            Text("Preview")
                .foregroundStyle(.secondary)
            Spacer()
            Text(previewNumber)
                .font(.system(.subheadline, design: .monospaced).bold())
                .foregroundStyle(Color.brand)
        }

        TextField("Prefix (e.g. QUO)", text: $format.prefix)
            .autocapitalization(.allCharacters)
            .onChange(of: format.prefix) { v in
                format.prefix = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
            }

        Picker("Separator", selection: $format.separator) {
            ForEach(separators, id: \.0) { Text($0.1).tag($0.0) }
        }

        Picker("Date Format", selection: $format.dateFormat) {
            ForEach(dateFormats, id: \.0) { Text($0.1).tag($0.0) }
        }

        Picker("Sequence Digits", selection: $format.seqDigits) {
            ForEach([3, 4, 5, 6], id: \.self) { Text("\($0) digits").tag($0) }
        }
    }

    private var previewNumber: String {
        let now = Date()
        let cal = Calendar.current
        let yy   = String(format: "%02d", cal.component(.year,  from: now) % 100)
        let yyyy = String(cal.component(.year,  from: now))
        let mm   = String(format: "%02d", cal.component(.month, from: now))
        let dateStr: String
        switch format.dateFormat {
        case "YY":     dateStr = yy
        case "MM":     dateStr = mm
        case "YYMM":   dateStr = yy + mm
        case "MMYY":   dateStr = mm + yy
        case "YYYY":   dateStr = yyyy
        case "YYYYMM": dateStr = yyyy + mm
        default:       dateStr = ""
        }
        let seq = String(repeating: "0", count: max(0, format.seqDigits - 1)) + "1"
        let sep = format.separator
        return dateStr.isEmpty
            ? "\(format.prefix)\(sep)\(seq)"
            : "\(format.prefix)\(sep)\(dateStr)\(sep)\(seq)"
    }
}

struct MenuTile: View {
    let title:    String
    let icon:     String
    let color:    Color
    var disabled: Bool = false
    let action:   () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(disabled ? .secondary : color)
                    .frame(width: 52, height: 52)
                    .background(
                        (disabled ? Color.gray : color).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(disabled ? .tertiary : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}

// MARK: - Tenant settings

struct TenantSettingsView: View {
    @State private var settings: CompanySettings? = nil
    @State private var isLoading = true

    @State private var name               = ""
    @State private var email              = ""
    @State private var phone              = ""
    @State private var address            = ""
    @State private var taxRate            = "15"
    @State private var currency           = "ZAR"
    @State private var fiscalYearEndMonth = 12
    @State private var saving             = false
    @State private var error              = ""
    @State private var saved              = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading settings…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section("Company") {
                        TextField("Company name", text: $name)
                        TextField("Email",        text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress).autocapitalization(.none)
                        TextField("Phone",        text: $phone)
                            .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    }

                    Section("Address") {
                        TextField("Street address", text: $address, axis: .vertical)
                            .lineLimit(3)
                    }

                    Section("Billing defaults") {
                        HStack {
                            Text("Default tax rate (%)")
                            Spacer()
                            TextField("15", text: $taxRate)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                        Picker("Currency", selection: $currency) {
                            Text("ZAR — South African Rand").tag("ZAR")
                            Text("USD — US Dollar").tag("USD")
                            Text("EUR — Euro").tag("EUR")
                            Text("GBP — British Pound").tag("GBP")
                        }
                    }

                    Section("Financial Year") {
                        Picker("Fiscal year ends", selection: $fiscalYearEndMonth) {
                            ForEach(1...12, id: \.self) { m in
                                Text(Calendar.current.monthSymbols[m - 1]).tag(m)
                            }
                        }
                    }

                    if !error.isEmpty {
                        Section {
                            Text(error).foregroundStyle(.red).font(.caption)
                        }
                    }

                    if saved {
                        Section {
                            Label("Settings saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline.bold())
                        }
                    }
                }
            }
        }
        .navigationTitle("Company Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await save() } } label: {
                    if saving { ProgressView().scaleEffect(0.8) } else { Text("Save").fontWeight(.semibold) }
                }
                .disabled(saving || isLoading)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        if let s: CompanySettings = try? await APIService.shared.get("/settings/company") {
            settings           = s
            name               = s.name         ?? ""
            email              = s.contactEmail ?? ""
            phone              = s.contactPhone ?? ""
            address            = s.address      ?? ""
            taxRate            = s.taxRate.map { String(format: "%.0f", $0) } ?? "15"
            currency           = s.currency     ?? "ZAR"
            fiscalYearEndMonth = s.settings?.fiscalYearEndMonth ?? 12
        }
        isLoading = false
    }

    private func save() async {
        saving = true; error = ""; saved = false
        do {
            let body = UpdateCompanySettings(
                name:         name.isEmpty    ? nil : name.trimmingCharacters(in: .whitespaces),
                contactEmail: email.isEmpty   ? nil : email,
                contactPhone: phone.isEmpty   ? nil : phone,
                address:      address.isEmpty ? nil : address.trimmingCharacters(in: .whitespaces),
                taxRate:      Double(taxRate) ?? 15,
                currency:     currency,
                settings:     CompanyDocumentSettings(
                    quoteNumberFormat:   nil,
                    invoiceNumberFormat: nil,
                    fiscalYearEndMonth:  fiscalYearEndMonth
                )
            )
            let _: CompanySettings = try await APIService.shared.patch("/settings/company", body: body)
            saved = true
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}
