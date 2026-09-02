import Persistence
import SwiftUI

/// Audit trail viewer (spec §4.6 / §6.3.3): lists persisted records, offers
/// export to a share sheet and a clear-all action.
struct AuditView: View {
    @Environment(AuditManager.self) private var audit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if audit.entries.isEmpty {
                    ContentUnavailableView("audit.empty", systemImage: "doc.text.magnifyingglass")
                } else {
                    ForEach(audit.entries, id: \.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.toolName)
                                    .font(.headline)
                                Spacer()
                                Text(outcomeLabel(entry.outcomeRaw))
                                    .font(.caption)
                                    .foregroundStyle(outcomeColor(entry.outcomeRaw))
                            }
                            Text(entry.commandText)
                                .font(.system(.caption, design: .monospaced))
                            Text("\(entry.approver) · \(entry.strategyRaw) · \(Self.timeFormatter.string(from: entry.timestamp))")
                                .font(.caption2)
                                .foregroundStyle(Color.glassSecondaryText)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(Text("audit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("audit.export", systemImage: "square.and.arrow.up") {
                        export()
                    }
                    .disabled(audit.entries.isEmpty)
                    Button("audit.clear", systemImage: "trash", role: .destructive) {
                        audit.clear()
                    }
                    .disabled(audit.entries.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func export() {
        let text = audit.exportText()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("audit.log")
        try? text.write(to: temp, atomically: true, encoding: .utf8)
        let controller = UIActivityViewController(activityItems: [temp], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController
        {
            root.present(controller, animated: true)
        }
    }

    private func outcomeLabel(_ raw: String) -> String {
        switch raw {
        case "autoApproved": String(localized: "audit.outcome.autoApproved")
        case "userApproved": String(localized: "audit.outcome.userApproved")
        case "editedApproved": String(localized: "audit.outcome.editedApproved")
        case "rejected": String(localized: "audit.outcome.rejected")
        case "denied": String(localized: "audit.outcome.denied")
        case "cancelled": String(localized: "audit.outcome.cancelled")
        case "failed": String(localized: "audit.outcome.failed")
        default: raw
        }
    }

    private func outcomeColor(_ raw: String) -> Color {
        switch raw {
        case "autoApproved", "userApproved", "editedApproved": .glassAccent
        case "rejected", "denied", "cancelled", "failed": .glassDanger
        default: .glassSecondaryText
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
