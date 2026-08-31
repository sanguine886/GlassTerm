import Foundation

/// One button on the iOS extension keyboard bar (spec §4.3). `output` is the
/// byte sequence sent to the terminal; variants appear on long-press.
public struct KeyboardKey: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let label: String
    public let output: String
    public let variants: [String]

    public init(id: String, label: String, output: String, variants: [String] = []) {
        self.id = id
        self.label = label
        self.output = output
        self.variants = variants
    }

    /// Full set including long-press variants, for the HUD.
    public var allOutputs: [String] {
        [output] + variants
    }
}

/// Editable layout for the iOS extension keyboard bar. Serializable as JSON so
/// users can save their own layouts (spec §4.3: 支持用户编辑按键布局).
public struct KeyboardLayout: Equatable, Sendable, Codable {
    public let name: String
    public let keys: [KeyboardKey]

    public init(name: String, keys: [KeyboardKey]) {
        self.name = name
        self.keys = keys
    }

    public static let `default` = KeyboardLayout(
        name: "Default",
        keys: [
            KeyboardKey(id: "esc", label: "esc", output: "\u{1B}", variants: ["\u{1B}["]),
            KeyboardKey(id: "tab", label: "tab", output: "\t"),
            KeyboardKey(id: "ctrl", label: "ctrl", output: "\u{1B}", variants: ["\u{1B}[", "\u{1B}]"]),
            KeyboardKey(id: "up", label: "↑", output: "\u{1B}[A"),
            KeyboardKey(id: "down", label: "↓", output: "\u{1B}[B"),
            KeyboardKey(id: "right", label: "→", output: "\u{1B}[C"),
            KeyboardKey(id: "left", label: "←", output: "\u{1B}[D"),
            KeyboardKey(id: "home", label: "home", output: "\u{1B}[H", variants: ["\u{1B}[1~"]),
            KeyboardKey(id: "end", label: "end", output: "\u{1B}[F", variants: ["\u{1B}[4~"]),
            KeyboardKey(id: "pgup", label: "pgup", output: "\u{1B}[5~"),
            KeyboardKey(id: "pgdn", label: "pgdn", output: "\u{1B}[6~"),
            KeyboardKey(id: "pipe", label: "|", output: "|"),
            KeyboardKey(id: "tilde", label: "~", output: "~"),
            KeyboardKey(id: "amp", label: "&", output: "&"),
            KeyboardKey(id: "semicolon", label: ";", output: ";"),
            KeyboardKey(id: "dollar", label: "$", output: "$"),
            KeyboardKey(id: "underscore", label: "_", output: "_"),
            KeyboardKey(id: "dash", label: "-", output: "-"),
        ]
    )

    public func key(id: String) -> KeyboardKey? {
        keys.first { $0.id == id }
    }

    // MARK: - Persistence (user-edited layouts)

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) -> KeyboardLayout? {
        try? JSONDecoder().decode(KeyboardLayout.self, from: data)
    }
}
