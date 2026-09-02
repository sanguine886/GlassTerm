import Foundation

/// Detects whether the remote shell is running inside tmux (spec §4.2: 检测到
/// tmux 会话时提示 attach). Triggered by the DA1 response `CSI ? 62 c` (tmux
/// device attribute) or the tmux DCS prefix `ESC P tmux;`.
public enum TmuxDetector {
    public static let tmuxDA1 = "\u{1B}[?62c"

    /// Checks a chunk of terminal output for tmux markers. The check is
    /// stateless per chunk; callers should not expect markers to span chunks
    /// (tmux sends them atomically).
    public static func containsTmuxMarker(in data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(tmuxDA1) || text.contains("\u{1B}Ptmux;")
    }
}
