import SwiftUI

struct QuoteDetailView: View {
    let quote: Quote

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Quote #", value: quote.number)
                LabeledContent("Status") { StatusBadge(status: quote.status) }
                if let contact = quote.contact {
                    LabeledContent("Contact", value: contact.displayName)
                }
                if let project = quote.projectName {
                    LabeledContent("Project", value: project)
                }
                if let validUntil = quote.validUntil {
                    LabeledContent("Valid Until", value: formattedDate(validUntil))
                }
            }

            Section("Line Items") {
                ForEach(quote.lineItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.description)
                            .font(.subheadline)
                        HStack {
                            Text("\(item.quantity, specifier: "%.0f") × \(item.unitPrice, format: .currency(code: "ZAR"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(item.total, format: .currency(code: "ZAR"))
                                .font(.subheadline.bold())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Summary") {
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(quote.subtotal, format: .currency(code: "ZAR"))
                }
                if quote.tax > 0 {
                    HStack {
                        Text("Tax")
                        Spacer()
                        Text(quote.tax, format: .currency(code: "ZAR"))
                    }
                }
                HStack {
                    Text("Total")
                        .bold()
                    Spacer()
                    Text(quote.total, format: .currency(code: "ZAR"))
                        .bold()
                        .foregroundStyle(.orange)
                }
            }

            if let notes = quote.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Quote \(quote.number)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formattedDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) else { return iso }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }
}
