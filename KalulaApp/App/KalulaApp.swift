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
                    .tabItem { Label("Sales", systemImage: "doc.text.fill") }

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Scanner
                    MenuSection(title: "Scanner") {
                        HStack(spacing: 12) {
                            MenuTile(title: "Scan Quote",     icon: "doc.text.magnifyingglass", color: .orange) {
                                appState.scannerType = .vendorQuote; appState.showScanner = true; dismiss()
                            }
                            MenuTile(title: "Scan Receipt",   icon: "receipt",                  color: .mint) {
                                appState.scannerType = .receipt;     appState.showScanner = true; dismiss()
                            }
                            MenuTile(title: "Scan Document",  icon: "doc.badge.plus",            color: .blue) {
                                appState.scannerType = .general;     appState.showScanner = true; dismiss()
                            }
                        }
                    }

                    // Documents
                    MenuSection(title: "Storage") {
                        HStack(spacing: 12) {
                            MenuTile(title: "Documents", icon: "folder.fill", color: .indigo) {
                                showDocuments = true
                            }
                            MenuTile(title: "Receipts", icon: "receipt.fill", color: .green) {
                                showReceipts = true
                            }
                            Spacer()
                        }
                    }

                    // Coming soon
                    MenuSection(title: "Coming Soon") {
                        HStack(spacing: 12) {
                            MenuTile(title: "Tickets",    icon: "ticket",           color: .gray, disabled: true) {}
                            MenuTile(title: "Analytics",  icon: "chart.bar.fill",   color: .gray, disabled: true) {}
                            MenuTile(title: "Purchases",  icon: "cart.fill",        color: .gray, disabled: true) {}
                        }
                    }

                    // Sign out
                    Button(role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            auth.logout()
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .foregroundStyle(.red)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(isPresented: $showDocuments) { DocumentsView() }
            .navigationDestination(isPresented: $showReceipts)  { ReceiptsView() }
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
