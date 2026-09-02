import CoreSSH
import GlassKit
import Persistence
import SwiftUI
import TerminalKit
import UIKit

/// Full terminal screen (spec P2): SwiftTerm view bridged to the SSH PTY,
/// extension keyboard bar, glass session tabs, tmux attach hint.
struct TerminalScreenView: View {
    let record: HostRecord

    @Environment(HostManager.self) private var manager
    @State private var prefs = TerminalPreferences.shared
    @State private var terminalSession: TerminalSession?
    @State private var tabs = SessionTabsModel()
    @State private var pendingFlow: ConnectFlow?
    @State private var errorMessage: String?
    @State private var showTmuxHint = false
    @State private var isOpening = false
    /// Session/config of the attempt awaiting a fingerprint decision.
    @State private var pendingSession: SSHSession?
    @State private var pendingConfig: SSHHostConfig?
    /// The live SSH session backing the terminal. Held here so closing the tab
    /// or leaving the screen actually disconnects the remote shell/PTY instead
    /// of leaking it (spec §4.2 lifecycle).
    @State private var session: SSHSession?

    var body: some View {
        VStack(spacing: 0) {
            if let terminalSession {
                TerminalViewWrapper(session: terminalSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.keyboard)
            } else {
                openingState
            }
            if !tabs.tabs.isEmpty {
                TerminalTabBar(model: tabs) { id in
                    closeSession(id: id)
                }
            }
        }
        .background(Color.black)
        .navigationTitle(Text(record.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                ExtensionKeyboardBar(layout: .default) { text in
                    terminalSession?.send(text)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("terminal.newSession", systemImage: "plus") {
                        openNewSession()
                    }
                    Button("terminal.disconnect", systemImage: "bolt.slash", role: .destructive) {
                        disconnectAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { openFirstSession() }
        .onDisappear {
            terminalSession?.stop()
            terminalSession = nil
            let stale = session
            session = nil
            if let stale {
                Task { await stale.disconnect() }
            }
        }
        .sheet(item: $pendingFlow) { flow in
            FingerprintConfirmView(kind: flow.kind) { decision in
                handleFingerprintDecision(decision, flow: flow)
            }
        }
        .alert(Text("tmux.detected.title"), isPresented: $showTmuxHint) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("tmux.detected.body")
        }
        .alert(
            Text("error.title"),
            isPresented: .init(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var openingState: some View {
        VStack(spacing: GlassSpacing.md) {
            if isOpening {
                ProgressView()
                Text("terminal.connecting")
                    .font(.footnote)
                    .foregroundStyle(Color.glassSecondaryText)
            } else {
                Button("terminal.reconnect", systemImage: "arrow.clockwise") {
                    openFirstSession()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sessions

    private func openFirstSession() {
        guard terminalSession == nil else { return }
        openNewSession()
    }

    private func openNewSession() {
        guard !isOpening else { return }
        isOpening = true
        Task {
            defer { isOpening = false }
            do {
                let (session, config) = try manager.openSession(for: record)
                try await startShell(session: session, config: config)
            } catch let error as SSHError {
                switch error {
                case let .hostKeyUnknown(fingerprint):
                    queueFingerprintFlow(.new(fingerprint))
                case let .hostKeyChanged(pinned, presented):
                    queueFingerprintFlow(.changed(pinned: pinned, presented: presented))
                default:
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func queueFingerprintFlow(_ kind: FingerprintFlowKind) {
        guard let pendingSession, let pendingConfig else {
            errorMessage = String(localized: "error.title")
            return
        }
        pendingFlow = ConnectFlow(record: record, session: pendingSession, config: pendingConfig, kind: kind)
    }

    private func startShell(session: SSHSession, config: SSHHostConfig) async throws {
        pendingSession = session
        pendingConfig = config
        try await session.connect(config: config, knownHosts: manager.knownHosts)
        manager.markConnected(record)
        try await attachShell(session)
    }

    private func attachShell(_ session: SSHSession) async throws {
        let shell = try await session.requestShell(cols: 40, rows: 16)
        let terminal = TerminalSession(
            shell: shell,
            fontName: prefs.fontName,
            fontSize: prefs.fontSize,
            theme: prefs.theme
        )
        terminal.onTmuxDetected = { showTmuxHint = true }
        terminalSession = terminal
        self.session = session
        _ = tabs.add(title: record.name)
    }

    private func handleFingerprintDecision(_ decision: Bool, flow: ConnectFlow) {
        pendingFlow = nil
        guard decision else { return }
        Task {
            do {
                switch flow.kind {
                case let .new(fingerprint):
                    manager.knownHosts.trust(hostIdentifier: flow.config.hostIdentifier, fingerprint: fingerprint)
                case let .changed(_, changed):
                    manager.knownHosts.repin(hostIdentifier: flow.config.hostIdentifier, fingerprint: changed)
                }
                try await flow.session.connect(config: flow.config, knownHosts: manager.knownHosts)
                manager.markConnected(flow.record)
                try await attachShell(flow.session)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func closeSession(id: UUID) {
        tabs.close(id: id)
        if tabs.tabs.isEmpty {
            terminalSession?.stop()
            terminalSession = nil
            Task { await session?.disconnect() }
            session = nil
        }
    }

    private func disconnectAll() {
        terminalSession?.stop()
        terminalSession = nil
        let stale = session
        session = nil
        if let stale {
            Task { await stale.disconnect() }
        }
        tabs = SessionTabsModel()
    }
}

/// UIViewRepresentable bridge for SwiftTerm's TerminalView.
private struct TerminalViewWrapper: UIViewRepresentable {
    let session: TerminalSession

    func makeUIView(context _: Context) -> UIView {
        // A host view that fills the phone and, on every layout, resizes the
        // SwiftTerm terminal to the actual column/row count for its bounds.
        // This is what keeps the CLI from overflowing the screen (真机验收:
        // 终端宽度>屏幕). Auto Layout alone does not resize the emulator.
        let host = TerminalHostView()
        host.backgroundColor = .black
        host.attach(session.terminalView)
        return host
    }

    func updateUIView(_ container: UIView, context _: Context) {
        guard let host = container as? TerminalHostView else { return }
        host.attach(session.terminalView)
        host.setNeedsLayout()
    }
}

/// Host UIView that owns a SwiftTerm terminal and re-sizes it to fit its own
/// bounds. `layoutSubviews` runs on every size change (rotation, split, launch),
/// so the terminal always matches the phone's width.
private final class TerminalHostView: UIView {
    private var terminalView: TerminalView?

    func attach(_ terminal: TerminalView) {
        if terminalView === terminal {
            return
        }
        terminalView?.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        terminalView = terminal
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let terminal = terminalView else { return }
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }

        // Compute how many fixed-width cells fit the host.
        let cellWidth = terminal.cellSize.width
        let cellHeight = terminal.cellSize.height
        let cols = max(Int(width / cellWidth), 1)
        let rows = max(Int(height / cellHeight), 1)
        if let terminalState = terminal.terminal, terminalState.cols != cols || terminalState.rows != rows {
            terminalState.resize(cols: cols, rows: rows, pixelWidth: Int(width), pixelHeight: Int(height))
        }
    }
}
