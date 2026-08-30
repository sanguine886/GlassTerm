import GlassKit
import SwiftUI

struct ServersView: View {
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("tab.servers"))
                .background(Color.glassBackground.ignoresSafeArea())
        }
    }

    private var content: some View {
        GlassEffectContainer(spacing: GlassSpacing.md) {
            ScrollView {
                VStack(spacing: GlassSpacing.md) {
                    PlaceholderSection(
                        headingID: "screen.servers.heading",
                        titleKey: "placeholder.servers.title",
                        bodyKey: "placeholder.servers.body"
                    )
                    GlassCard {
                        Text("placeholder.servers.hint")
                            .font(.footnote)
                            .foregroundStyle(Color.glassSecondaryText)
                    }
                }
                .padding(GlassSpacing.lg)
            }
        }
    }
}
