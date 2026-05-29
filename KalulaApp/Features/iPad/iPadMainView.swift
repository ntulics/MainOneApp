import SwiftUI

// MARK: - Destination

enum AppDestination: Hashable {
    case dashboard
    case customers
    case suppliers
    case sales
    case purchases
    case documents(DocumentType?)   // nil = all types
    case importantHub
    case companySettings
    case preferences
}

// MARK: - iPad root

struct iPadMainView: View {
    @EnvironmentObject var auth:     AuthService
    @EnvironmentObject var appState: AppState
    @State private var selection: AppDestination? = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            iPadSidebarView(selection: $selection, columnVisibility: $columnVisibility)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard:
                iPadDashboardView()
            case .customers:
                CustomersView()
            case .suppliers:
                SuppliersView()
            case .sales:
                SalesView()
            case .purchases:
                PurchasesView()
            case .documents(let type):
                DocumentsView(initialType: type)
            case .importantHub:
                ImportantDocumentsView()
            case .companySettings:
                TenantSettingsView()
            case .preferences:
                PreferencesView()
            }
        }
        .fullScreenCover(isPresented: $appState.showScanner) {
            ScannerView(initialType: appState.scannerType)
        }
    }
}

// MARK: - Sidebar

struct iPadSidebarView: View {
    @Binding var selection:        AppDestination?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @EnvironmentObject var auth:     AuthService
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            profileHeader
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            List(selection: $selection) {

                // ── Main ────────────────────────────────────────────────────
                Section("Main") {
                    SidebarRow(icon: "house.fill", label: "Dashboard", color: .orange)
                        .tag(AppDestination.dashboard)
                }

                // ── Business ────────────────────────────────────────────────
                Section("Business") {
                    SidebarRow(icon: "person.2.fill",       label: "Customers",  color: .blue)
                        .tag(AppDestination.customers)
                    SidebarRow(icon: "shippingbox.fill",    label: "Suppliers",  color: .green)
                        .tag(AppDestination.suppliers)
                    SidebarRow(icon: "doc.text.fill",       label: "Sales",      color: .indigo)
                        .tag(AppDestination.sales)
                    SidebarRow(icon: "cart.fill",           label: "Purchases",  color: .orange)
                        .tag(AppDestination.purchases)
                }

                // ── Documents ───────────────────────────────────────────────
                Section("Documents") {
                    SidebarRow(icon: "folder.fill", label: "All Documents", color: .indigo)
                        .tag(AppDestination.documents(nil))
                    SidebarRow(icon: "star.fill",   label: "Important",     color: .yellow)
                        .tag(AppDestination.importantHub)
                }

                // ── Settings ────────────────────────────────────────────────
                Section("Settings") {
                    SidebarRow(icon: "building.2.fill", label: "Company",     color: .blue)
                        .tag(AppDestination.companySettings)
                    SidebarRow(icon: "gearshape.fill",  label: "Preferences", color: .orange)
                        .tag(AppDestination.preferences)
                }
            }
            .listStyle(.sidebar)
            .tint(Color(.systemGray4))

            Divider()

            Button(role: .destructive) {
                auth.logout()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            .foregroundStyle(.red)
            .font(.system(size: 14, weight: .medium))
        }
        .navigationBarHidden(true)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Profile header

    private var profileHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 52, height: 52)
                Text(auth.currentUser?.initials ?? "?")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(auth.currentUser?.displayName ?? "")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Last sync: \(Date(), style: .time)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Collapse sidebar button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    columnVisibility = .detailOnly
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    let icon:     String
    let label:    String
    let color:    Color
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(disabled ? Color(.tertiaryLabel) : color)
                .frame(width: 28, height: 28)
                .background(
                    (disabled ? Color.gray : color).opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 7)
                )

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(disabled ? Color(.tertiaryLabel) : .primary)
        }
        .opacity(disabled ? 0.5 : 1)
    }
}
