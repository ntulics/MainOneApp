import SwiftUI

// MARK: - MainOne brand palette
//
// Single source of truth — update here to retheme the whole app.
//
//  .brand     → primary purple  #5C3FC8  (replaces .orange throughout)
//  .brandCTA  → amber CTA       #FFB400  (warm accent, pending/warning states)

extension Color {
    /// Primary brand purple  #5C3FC8
    static let brand    = Color(red: 0.361, green: 0.247, blue: 0.784)
    /// Amber CTA / warning   #FFB400
    static let brandCTA = Color(red: 1.000, green: 0.706, blue: 0.000)
}
