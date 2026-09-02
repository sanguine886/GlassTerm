import CoreSSH
import Foundation
import GlassKit
import Observation
import Persistence
import SwiftData
import SwiftUI

enum FingerprintFlowKind: Equatable {
    case new(HostKeyFingerprint)
    case changed(pinned: HostKeyFingerprint, presented: HostKeyFingerprint)
}

/// A pending connect attempt that is waiting for a host-key decision.
struct ConnectFlow: Identifiable {
    let id = UUID()
    let record: HostRecord
    let session: SSHSession
    let config: SSHHostConfig
    let kind: FingerprintFlowKind
}

struct ServersView: View {
    @Environment(HostManager.self) private var manager
    @Query(sort: \HostRecord.createdAt) private var hosts: [HostRecord]

    @State private var showAdd = false
    @State private var editingHost: HostRecord?
    @State private var flow: ConnectFlow?
    @State private var path: [UUID] = []
    @State private var errorMessage: String?
    @State private var connectingHostID: UUID?
    @State private var sftpHost: HostRecord?

    /// `@Query`'s macro-generated private initializer suppresses the default
    /// `init()`, so it is declared explicitly (SwiftData stores + environment
    /// object are bootstrapped here).
    init() {
        _manager = Environment(HostManager.self)
        _hosts = Query(sort: [SortDescriptor(\HostRecord.createdAt)])
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(Text("tab.servers"))
                .background(Color.glassBackground.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("screen.servers.add")
                        .accessibilityLabel(Text("host.add"))
                    }
                }
                .navigationDestination(for: UUID.self) { hostID in
                    if let record = manager.record(id: hostID) {
                        TerminalScreenView(record: record)
                    }
                }
                .sheet(isPresented: $showAdd) {
                    AddEditHostView(existing: nil)
                }
                .sheet(item: $editingHost) { record in
                    AddEditHostView(existing: record)
                }
                .sheet(item: $flow) { pending in
                    FingerprintConfirmView(kind: pending.kind) { decision in
                        handleFingerprintDecision(decision, flow: pending)
                    }
                }
                .sheet(item: $sftpHost) { host in
                    NavigationStack {
                        SFTPBrowserView(record: host)
                    }
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
    }

    private var content: some View {
        GlassEffectContainer(spacing: GlassSpacing.md) {
            ScrollView {
                VStack(spacing: GlassSpacing.md) {
                    if hosts.isEmpty {
                        PlaceholderSection(
                            headingID: "screen.servers.heading",
                            titleKey: "host.empty.title",
                            bodyKey: "host.empty.body"
                        )
                    } else {
                        ForEach(hosts, id: \.id) { record in
                            hostCard(record)
                        }
                    }
                }
                .padding(GlassSpacing.lg)
            }
        }
    }

    private func hostCard(_ record: HostRecord) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: GlassSpacing.sm) {
                HStack {
                    Text(record.name)
                        .font(.headline)
                        .foregroundStyle(Color.glassPrimaryText)
                    Spacer()
                    if connectingHostID == record.id {
                        ProgressView()
                    }
                }
                Text("\(record.username)@\(record.hostname):\(record.port)")
                    .font(.glassMono(13))
                    .foregroundStyle(Color.glassSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    if let group = record.group, !group.isEmpty {
                        Label(group, systemImage: "tag")
                            .font(.caption)
                            .foregroundStyle(Color.glassSecondaryText)
                    }
                    Spacer()
                    if let last = record.lastConnectedAt {
                        Text("host.lastConnected \(Text(last, style: .relative))")
                            .font(.caption2)
                            .foregroundStyle(Color.glassSecondaryText)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { connect(record) }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("host.card.\(record.id.uuidString)")
        }
        .contextMenu {
            Button("common.edit") { editingHost = record }
            Button("sftp.open", systemImage: "folder") { sftpHost = record }
            Button("common.delete", role: .destructive) {
                try? manager.delete(record)
            }
        }
    }

    private func connect(_ record: HostRecord) {
        guard connectingHostID == nil else {
            return
        }
        connectingHostID = record.id
        Task {
            defer { connectingHostID = nil }
            await connectAndNavigate(record)
        }
    }

    private func connectAndNavigate(_ record: HostRecord) async {
        let (session, config): (SSHSession, SSHHostConfig)
        do {
            (session, config) = try manager.openSession(for: record)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        do {
            try await session.connect(config: config, knownHosts: manager.knownHosts)
            manager.markConnected(record)
            path.append(record.id)
        } catch let error as SSHError {
            switch error {
            case let .hostKeyUnknown(fingerprint):
                flow = ConnectFlow(
                    record: record, session: session, config: config,
                    kind: .new(fingerprint)
                )
            case let .hostKeyChanged(pinned, presented):
                flow = ConnectFlow(
                    record: record, session: session, config: config,
                    kind: .changed(pinned: pinned, presented: presented)
                )
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleFingerprintDecision(_ decision: Bool, flow: ConnectFlow) {
        guard decision else {
            Task { await flow.session.disconnect() }
            return
        }
        Task {
            switch flow.kind {
            case let .new(fingerprint):
                manager.knownHosts.trust(hostIdentifier: flow.config.hostIdentifier, fingerprint: fingerprint)
            case let .changed(_, changed):
                manager.knownHosts.repin(hostIdentifier: flow.config.hostIdentifier, fingerprint: changed)
            }

            do {
                try await flow.session.connect(config: flow.config, knownHosts: manager.knownHosts)
                manager.markConnected(flow.record)
                self.flow = nil
                path.append(flow.record.id)
            } catch {
                self.flow = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}
