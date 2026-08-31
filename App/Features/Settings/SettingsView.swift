import GlassKit
import SwiftUI
import TerminalKit

struct SettingsView: View {
    @State private var prefs = TerminalPreferences.shared

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("tab.settings"))
                .background(Color.glassBackground.ignoresSafeArea())
        }
    }

    private var content: some View {
        GlassEffectContainer(spacing: GlassSpacing.md) {
            ScrollView {
                VStack(spacing: GlassSpacing.md) {
                    terminalSection
                }
                .padding(GlassSpacing.lg)
            }
        }
    }

    private var terminalSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: GlassSpacing.md) {
                Text("settings.terminal.heading")
                    .font(.headline)
                    .foregroundStyle(Color.glassPrimaryText)

                Picker("settings.terminal.font", selection: $prefs.fontName) {
                    ForEach(TerminalFontSpec.builtInNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("settings.terminal.size")
                    Spacer()
                    Stepper(
                        "\(prefs.fontSize) pt",
                        value: Binding(
                            get: { prefs.fontSize },
                            set: { prefs.saveSize($0) }
                        ),
                        in: TerminalFontSpec.sizeRange
                    )
                    .accessibilityIdentifier("settings.fontSize")
                }

                Picker("settings.terminal.theme", selection: $prefs.themeName) {
                    ForEach(TerminalTheme.all, id: \.name) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.theme")
            }
        }
    }
}
