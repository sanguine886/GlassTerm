import GlassKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("tab.settings"))
                .background(Color.glassBackground.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) {
                    GlassBar {
                        GlassButton("sample.theme", systemImage: "paintpalette") {}
                        GlassButton("sample.keyboard", systemImage: "keyboard") {}
                    }
                }
        }
    }

    private var content: some View {
        GlassEffectContainer(spacing: GlassSpacing.md) {
            ScrollView {
                VStack(spacing: GlassSpacing.md) {
                    PlaceholderSection(
                        headingID: "screen.settings.heading",
                        titleKey: "placeholder.settings.title",
                        bodyKey: "placeholder.settings.body"
                    )
                }
                .padding(GlassSpacing.lg)
            }
        }
    }
}
