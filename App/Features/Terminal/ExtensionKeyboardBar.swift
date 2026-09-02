import SwiftUI
import TerminalKit

/// The iOS extension keyboard bar (spec §4.3): Esc/Tab/Ctrl/arrows/Home/End/
/// pipe/tilde and common symbols, rendered in the keyboard toolbar area.
/// Long-press shows a key's variants.
struct ExtensionKeyboardBar: View {
    let layout: KeyboardLayout
    let onSend: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(layout.keys) { key in
                    KeyboardKeyButton(key: key, onSend: onSend)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.thinMaterial)
    }
}

private struct KeyboardKeyButton: View {
    let key: KeyboardKey
    let onSend: (String) -> Void

    @State private var selectedVariant: String?

    var body: some View {
        Menu {
            ForEach(key.variants, id: \.self) { variant in
                Button(displayLabel(variant)) {
                    onSend(variant)
                }
            }
        } label: {
            Text(key.label)
                .font(.system(.footnote, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.glassSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } primaryAction: {
            onSend(key.output)
        }
    }

    /// Human-readable label for control-byte variants.
    private func displayLabel(_ output: String) -> String {
        switch output {
        case "\u{1B}": "ESC"
        case "\u{1B}[": "ESC ["
        case "\u{1B}]": "ESC ]"
        case "\u{1B}[1~": "Home"
        case "\u{1B}[4~": "End"
        default: output
        }
    }
}
