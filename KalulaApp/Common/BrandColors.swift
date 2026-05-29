import SwiftUI

// MARK: - MainOne brand palette
//
// Single source of truth — update here to retheme the whole app.
//
//  .brand     → primary blue    #1366EF
//  .brandCTA  → amber CTA       #FFB400  (warm accent, pending/warning states)

extension Color {
    /// Primary brand blue   #1366EF
    static let brand    = Color(red: 0.075, green: 0.400, blue: 0.937)
    /// Amber CTA / warning  #FFB400
    static let brandCTA = Color(red: 1.000, green: 0.706, blue: 0.000)
}
