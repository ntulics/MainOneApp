import SwiftUI

// MARK: - View model

@MainActor
final class CustomersViewModel: ObservableObject {
    @Published var contacts:  [CRMContact] = []
    @Published var isLoading  = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    var filtered: [CRMContact] {
        guard !searchText.isEmpty else { return contacts }
        let q = searchText.lowercased()
        return contacts.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.email?.lowercased().contains(q) == true)
            || ($0.phone?.contains(q) == true)
        }
    }

    func load() async {
        isLoading    = true
        errorMessage = nil
        do {
            let res: ContactsResponse = try await APIService.shared.get("/crm/contacts")
            contacts = res.contacts
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ contact: CRMContact) async {
        try? await APIService.shared.delete("/crm/contacts/\(contact.id)")
        contacts.removeAll { $0.id == contact.id }
    }
}

// MARK: - Main view

struct CustomersView: View {
    @StateObject private var vm = CustomersViewModel()
    @State private var showNewContact = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if vm.isLoading && vm.contacts.isEmpty {
                        ProgressView("Loading customers…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = vm.errorMessage {
                        ErrorView(message: err) { Task { await vm.load() } }
                    } else if vm.filtered.isEmpty {
                        EmptyStateView(
                            icon:    "person.2",
                            title:   "No Clients",
                            message: vm.searchText.isEmpty
                                ? "Add your first client using the + button."
                                : "No results for \u{201C}\(vm.searchText)\u{201D}"
                        )
                    } else {
                        List {
                            ForEach(vm.filtered) { contact in
                                ContactRow(contact: contact)
                            }
                            .onDelete { idx in
                                let items = idx.map { vm.filtered[$0] }
                                Task { for c in items { await vm.delete(c) } }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await vm.load() }
                    }
                }
                .searchable(text: $vm.searchText, prompt: "Search clients")
                .navigationTitle("Clients")
                .navigationBarTitleDisplayMode(.large)
                .task { await vm.load() }

                // FAB
                if !showNewContact {
                    FABButton { showNewContact = true }
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: showNewContact)
        }
        .sheet(isPresented: $showNewContact, onDismiss: {
            Task { await vm.load() }
        }) {
            NewContactSheet(isPresented: $showNewContact)
        }
    }
}

// MARK: - Contact row

struct ContactRow: View {
    let contact: CRMContact

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(avatarColor(contact.displayName).opacity(0.15))
                .frame(width: 46, height: 46)
                .overlay(
                    Text(contact.initials)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(avatarColor(contact.displayName))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(contact.email ?? contact.phone ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let status = contact.status {
                Text(status.capitalized)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(status).opacity(0.12), in: Capsule())
                    .foregroundStyle(statusColor(status))
            }
        }
        .padding(.vertical, 6)
    }

    private func avatarColor(_ name: String) -> Color {
        let colors: [Color] = [.orange, .blue, .purple, .green, .pink, .indigo, .teal]
        return colors[abs(name.hashValue) % colors.count]
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "CLIENT":   return .green
        case "LEAD":     return Color(red: 0, green: 0.478, blue: 1)
        case "PROSPECT": return Color(red: 0.686, green: 0.322, blue: 0.871)
        default:         return Color(.systemGray)
        }
    }
}

// MARK: - New contact sheet

struct NewContactSheet: View {
    @Binding var isPresented: Bool
    @State private var firstName = ""
    @State private var lastName  = ""
    @State private var email     = ""
    @State private var phone     = ""
    @State private var saving    = false
    @State private var error     = ""

    private var isValid: Bool { !firstName.isEmpty && !lastName.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Last name",  text: $lastName)
                        .textContentType(.familyName)
                }

                Section("Contact details") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone number",  text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                if !error.isEmpty {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(!isValid || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        error  = ""
        do {
            let body = CreateContactRequest(
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName:  lastName.trimmingCharacters(in: .whitespaces),
                email:     email.isEmpty ? nil : email,
                phone:     phone.isEmpty ? nil : phone,
                status:    "LEAD"
            )
            let _: CRMContact = try await APIService.shared.post("/crm/contacts", body: body)
            isPresented = false
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}
