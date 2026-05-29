import SwiftUI

/// Floating Action Button — used in Customers, Quotes, Invoices tabs.
struct FABButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.55, blue: 0.1), Color.brand],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .shadow(color: Color.brand.opacity(0.45), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}
