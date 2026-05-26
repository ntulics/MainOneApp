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
            if auth.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
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
                    .tabItem { Label("Clients", systemImage: "person.2.fill") }

                InvoicesListView()
                    .tabItem { Label("Invoices", systemImage: "doc.text.fill") }

                QuotesListView()
                    .tabItem { Label("Quotes", systemImage: "list.clipboard.fill") }
            }
            .tint(.orange)
        }
        .sheet(isPresented: $appState.showMore) {
            MoreMenuSheet()
        }
        .fullScreenCover(isPresented: $appState.showScanner) {
            ScannerView(initialType: appState.scannerType)
        }
    }
}

// MARK: - More menu sheet

struct MoreMenuSheet: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showDocuments = false
    @State private var showReceipts  = false
    @State private var showSettings  = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {

                        // Scanner
                        MenuSection(title: "Scanner") {
                            HStack(spacing: 12) {
                                MenuTile(title: "Scan Quote",    icon: "doc.text.magnifyingglass", color: .orange) {
                                    appState.scannerType = .vendorQuote; appState.showScanner = true; dismiss()
                                }
                                MenuTile(title: "Scan Receipt",  icon: "receipt",                  color: .mint) {
                                    appState.scannerType = .receipt;     appState.showScanner = true; dismiss()
                                }
                                MenuTile(title: "Scan Document", icon: "doc.badge.plus",            color: .blue) {
                                    appState.scannerType = .general;     appState.showScanner = true; dismiss()
                                }
                            }
                        }

                        // Storage
                        MenuSection(title: "Storage") {
                            HStack(spacing: 12) {
                                MenuTile(title: "Documents", icon: "folder.fill",  color: .indigo) { showDocuments = true }
                                MenuTile(title: "Receipts",  icon: "receipt.fill", color: .green)  { showReceipts  = true }
                                Spacer()
                            }
                        }

                        // Settings
                        MenuSection(title: "Settings") {
                            HStack(spacing: 12) {
                                MenuTile(title: "Company",     icon: "building.2.fill",  color: .blue)   { showSettings = true }
                                MenuTile(title: "Preferences", icon: "gearshape.fill",   color: .gray, disabled: true) {}
                                Spacer()
                            }
                        }

                        // Coming soon
                        MenuSection(title: "Coming Soon") {
                            HStack(spacing: 12) {
                                MenuTile(title: "Tickets",   icon: "ticket",         color: .gray, disabled: true) {}
                                MenuTile(title: "Analytics", icon: "chart.bar.fill", color: .gray, disabled: true) {}
                                MenuTile(title: "Purchases", icon: "cart.fill",      color: .gray, disabled: true) {}
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 8)
                }

                // Sign out — pinned to bottom
                Divider()
                Button(role: .destructive) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { auth.logout() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, max(28, 16))
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .navigationDestination(isPresented: $showDocuments) { DocumentsView() }
            .navigationDestination(isPresented: $showReceipts)  { ReceiptsView() }
            .navigationDestination(isPresented: $showSettings)  { TenantSettingsView() }
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

    @State private var name     = ""
    @State private var email    = ""
    @State private var phone    = ""
    @State private var address  = ""
    @State private var taxRate  = "15"
    @State private var currency = "ZAR"
    @State private var saving   = false
    @State private var error    = ""
    @State private var saved    = false

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
            settings = s
            name     = s.name     ?? ""
            email    = s.email    ?? ""
            phone    = s.phone    ?? ""
            address  = s.address  ?? ""
            taxRate  = s.taxRate.map { String(format: "%.0f", $0) } ?? "15"
            currency = s.currency ?? "ZAR"
        }
        isLoading = false
    }

    private func save() async {
        saving = true; error = ""; saved = false
        do {
            let body = UpdateCompanySettings(
                name:     name.isEmpty    ? nil : name.trimmingCharacters(in: .whitespaces),
                email:    email.isEmpty   ? nil : email,
                phone:    phone.isEmpty   ? nil : phone,
                address:  address.isEmpty ? nil : address.trimmingCharacters(in: .whitespaces),
                taxRate:  Double(taxRate) ?? 15,
                currency: currency
            )
            let _: CompanySettings = try await APIService.shared.put("/settings/company", body: body)
            saved = true
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}
