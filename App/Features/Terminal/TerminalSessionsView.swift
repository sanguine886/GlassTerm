import GlassKit
import SwiftUI

/// Terminal tab: hosts the snippet command panel (spec §4.3). Active terminal
/// sessions live in TerminalScreenView reached from each server.
struct TerminalSessionsView: View {
    var body: some View {
        NavigationStack {
            SnippetsListView()
                .background(Color.glassBackground.ignoresSafeArea())
        }
    }
}