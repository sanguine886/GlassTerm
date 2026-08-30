import GlassKit
import SwiftUI

struct TerminalSessionsView: View {
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("tab.terminal"))
                .background(Color.glassBackground.ignoresSafeArea())
        }
    }

    private var content: some View {
        GlassEffectContainer(spacing: GlassSpacing.md) {
            ScrollView {
                VStack(spacing: GlassSpacing.md) {
                    PlaceholderSection(
                        headingID: "screen.terminal.heading",
                        titleKey: "placeholder.terminal.title",
                        bodyKey: "placeholder.terminal.body"
                    )
                    GlassCard {
                        Text("placeholder.terminal.hint")
                            .font(.footnote)
                            .foregroundStyle(Color.glassSecondaryText)
                    }
                }
                .padding(GlassSpacing.lg)
            }
        }
    }
}
