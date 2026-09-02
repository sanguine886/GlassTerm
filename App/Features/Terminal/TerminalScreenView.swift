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

    var body: some View {
        VStack(spacing: 0) {
            if let terminalSession {
                TerminalViewWrapper(session: terminalSession)
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
        }
    }

    private func disconnectAll() {
        terminalSession?.stop()
        terminalSession = nil
        tabs = SessionTabsModel()
    }
}

/// UIViewRepresentable bridge for SwiftTerm's TerminalView.
private struct TerminalViewWrapper: UIViewRepresentable {
    let session: TerminalSession

    func makeUIView(context _: Context) -> TerminalView {
        session.terminalView
    }

    func updateUIView(_: TerminalView, context _: Context) {}
}
