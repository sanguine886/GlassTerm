import CoreSSH
import Foundation

#if canImport(UIKit)
    import SwiftTerm
    import UIKit

    /// Bridges an SSH PTY (`ShellStreams` from CoreSSH) to a SwiftTerm
    /// `TerminalView` (spec §4.3). All interaction happens on the main actor:
    /// SwiftTerm views are UIKit-backed and the shell writer is thread-safe.
    @MainActor
    public final class TerminalSession: TerminalViewDelegate {
        public let terminalView: TerminalView
        public private(set) var title: String = ""
        public private(set) var currentDirectory: String?
        /// Set when tmux markers appear in the output (spec §4.2 attach hint).
        public var onTmuxDetected: (() -> Void)?

        private let stdin: ShellStdin
        private var outputTask: Task<Void, Never>?
        private let fontName: String
        private let fontSize: Int
        private let theme: TerminalTheme

        public init(
            shell: ShellStreams,
            fontName: String = "Menlo",
            fontSize: Int = 12,
            theme: TerminalTheme = .dark
        ) {
            self.stdin = shell.stdin
            self.fontName = fontName
            self.fontSize = fontSize
            self.theme = theme

            // Scrollback ≥ 10000 lines (spec §4.3).
            let options = TerminalOptions(scrollback: 10_000)
            terminalView = TerminalView(frame: .zero, options: options)
            terminalView.terminalDelegate = self
            applyStyle()

            outputTask = Task { [weak self] in
                for await event in shell.output {
                    await self?.handle(event)
                }
            }
        }

        deinit {
            outputTask?.cancel()
        }

        /// Feed one shell event into the emulator.
        private func handle(_ event: ShellEvent) {
            switch event {
            case let .stdout(data):
                terminalView.feed(byteArray: data)
                if TmuxDetector.containsTmuxMarker(in: data) {
                    onTmuxDetected?()
                }
            case let .stderr(data):
                terminalView.feed(byteArray: data)
            case .exited:
                break
            }
        }

        public func stop() {
            outputTask?.cancel()
            outputTask = nil
        }

        /// Sends bytes to the remote shell (extension keyboard bar, pastes).
        public func send(_ text: String) {
            Task { try? await stdin.write(Data(text.utf8)) }
        }

        private func applyStyle() {
            terminalView.nativeBackgroundColor = uiColor(theme.background)
            terminalView.nativeForegroundColor = uiColor(theme.foreground)
            terminalView.caretColor = uiColor(theme.cursor)
            terminalView.font = UIFont(name: fontName, size: CGFloat(fontSize))
                ?? UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
            terminalView.installColors(theme.ansi.map(swiftColor))
        }

        private func uiColor(_ rgba: TerminalRGBA) -> UIColor {
            UIColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        }

        private func swiftColor(_ rgba: TerminalRGBA) -> SwiftTerm.Color {
            SwiftTerm.Color(
                red8: UInt16(rgba.red * 255),
                green8: UInt16(rgba.green * 255),
                blue8: UInt16(rgba.blue * 255)
            )
        }

        // MARK: - TerminalViewDelegate

        public func send(source _: TerminalView, data: ArraySlice<UInt8>) {
            let payload = Data(data)
            Task { try? await stdin.write(payload) }
        }

        public func sizeChanged(source _: TerminalView, newCols: Int, newRows: Int) {
            Task { try? await stdin.resize(cols: newCols, rows: newRows) }
        }

        public func setTerminalTitle(source _: TerminalView, title: String) {
            self.title = title
        }

        public func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
            currentDirectory = directory
        }

        public func scrolled(source _: TerminalView, position _: Double) {}

        public func requestOpenLink(source _: TerminalView, link: String, params _: [String: String]) {
            guard let url = URL(string: link), UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)
        }

        public func clipboardCopy(source _: TerminalView, content: Data) {
            UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
        }

        public func rangeChanged(source _: TerminalView, startY _: Int, endY _: Int) {}
    }
#endif
