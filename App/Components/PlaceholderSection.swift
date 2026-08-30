import GlassKit
import SwiftUI

/// Shared placeholder block for P0 scaffold screens.
struct PlaceholderSection: View {
    let headingID: String
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: GlassSpacing.sm) {
                Text(titleKey)
                    .font(.headline)
                    .accessibilityIdentifier(headingID)
                Text(bodyKey)
                    .font(.subheadline)
                    .foregroundStyle(Color.glassSecondaryText)
            }
        }
    }
}
