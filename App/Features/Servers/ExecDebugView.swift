import CoreSSH
import GlassKit
import Persistence
import SwiftUI

/// Simple exec debug page (spec P1: 暂用简易 exec 调试页). The full terminal
/// lands in P2 via TerminalKit.
struct ExecDebugView: View {
    let record: HostRecord

    @Environment(HostManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var displayState: SSHSessionState = .idle
    @State private var command = ""
    @State private var outputLog = ""
    @State private var isRunning = false
    @State private var session: SSHSession?
    @State private var observation: Task<Void, Never>?

    var body: some View {
        GlassEffectContainer(spacing: GlassSpacing.md) {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassSpacing.md) {
                    statusCapsule

                    GlassCard {
                        VStack(alignment: .leading, spacing: GlassSpacing.sm) {
                            HStack(spacing: GlassSpacing.sm) {
                                TextField(Text("exec.placeholder"), text: $command)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.glassMono(13))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onSubmit(runCommand)
                                    .accessibilityIdentifier("exec.field.command")
                                GlassButton("exec.run", role: .prominent) {
                                    runCommand()
                                }
                                .disabled(isRunning || command.isEmpty)
                            }

                            Text(outputLog.isEmpty ? String(localized: "exec.output.empty") : outputLog)
                                .font(.glassMono(11))
                                .foregroundStyle(outputLog.isEmpty ? Color.glassSecondaryText : Color.glassPrimaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }

                    GlassButton("exec.disconnect", systemImage: "bolt.slash", role: .destructive) {
                        disconnectAndClose()
                    }
                }
                .padding(GlassSpacing.lg)
            }
        }
        .navigationTitle(Text("exec.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: attachSession)
        .onDisappear {
            observation?.cancel()
            observation = nil
            if let session {
                Task { await session.disconnect() }
            }
        }
    }

    private var statusCapsule: some View {
        HStack(spacing: GlassSpacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusKey)
                .font(.footnote)
                .foregroundStyle(Color.glassSecondaryText)
            Spacer()
            Text("\(record.username)@\(record.hostname)")
                .font(.caption)
                .foregroundStyle(Color.glassSecondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, GlassSpacing.md)
        .padding(.vertical, GlassSpacing.sm)
        .glassEffect(.regular, in: Capsule())
        .accessibilityIdentifier("exec.status")
    }

    private var statusColor: Color {
        switch displayState {
        case .connected: .green
        case .reconnecting: .orange
        case .failed: .glassDanger
        default: .glassSecondaryText
        }
    }

    private var statusKey: LocalizedStringKey {
        switch displayState {
        case .idle: "exec.status.idle"
        case .connecting: "exec.status.connecting"
        case .connected: "exec.status.connected"
        case .reconnecting: "exec.status.reconnecting"
        case .failed: "exec.status.failed"
        case .closed: "exec.status.closed"
        }
    }

    private func attachSession() {
        guard session == nil else { return }
        guard let (fresh, config) = try? manager.openSession(for: record) else {
            outputLog = String(localized: "exec.error.noCredentials")
            return
        }
        session = fresh
        observation = Task {
            let stream = await fresh.stateStream()
            for await state in stream {
                displayState = state
            }
        }
        Task {
            do {
                try await fresh.connect(config: config, knownHosts: manager.knownHosts)
                manager.markConnected(record)
            } catch {
                outputLog = error.localizedDescription
            }
        }
    }

    private func runCommand() {
        guard let session, !isRunning else { return }
        let toRun = command
        isRunning = true
        Task {
            defer { isRunning = false }
            do {
                let result = try await session.run(toRun)
                outputLog += "→ \(toRun)\n\(result)\n"
            } catch {
                outputLog += "→ \(toRun)\n✗ \(error.localizedDescription)\n"
            }
        }
    }

    private func disconnectAndClose() {
        Task {
            await session?.disconnect()
            dismiss()
        }
    }
}
