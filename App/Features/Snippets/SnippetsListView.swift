import CoreSSH
import GlassKit
import Persistence
import SwiftUI

/// Snippet library: list, create, delete and run saved commands (spec §4.3 /
/// §7 P3). Running executes the command on a chosen host via a fresh exec
/// channel and shows the output.
struct SnippetsListView: View {
    @Environment(HostManager.self) private var manager
    @Environment(SnippetManager.self) private var snippets

    @State private var showNew = false
    @State private var newName = ""
    @State private var newCommand = ""
    @State private var runningSnippet: SnippetRecord?
    @State private var output: String?
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if snippets.snippets.isEmpty {
                ContentUnavailableView("snippets.empty", systemImage: "terminal")
            } else {
                ForEach(snippets.snippets) { snippet in
                    snippetRow(snippet)
                }
            }
        }
        .navigationTitle(Text("tab.terminal"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("snippets.new", systemImage: "plus") {
                    showNew = true
                }
            }
        }
        .alert(Text("snippets.new"), isPresented: $showNew) {
            TextField("snippets.name", text: $newName)
            TextField("snippets.command", text: $newCommand)
            Button("common.save") {
                snippets.add(name: newName, command: newCommand)
                newName = ""
                newCommand = ""
            }
            Button("common.cancel", role: .cancel) {}
        }
        .alert(Text("error.title"), isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $runningSnippet) { snippet in
            runSheet(snippet)
        }
        .task { snippets.refresh() }
    }

    private func snippetRow(_ snippet: SnippetRecord) -> some View {
        Button {
            runningSnippet = snippet
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.name)
                    .font(.headline)
                Text(snippet.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.glassSecondaryText)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("snippets.run", systemImage: "play") { runningSnippet = snippet }
            Button("common.delete", systemImage: "trash", role: .destructive) {
                snippets.delete(snippet)
            }
        }
    }

    private func runSheet(_ snippet: SnippetRecord) -> some View {
        NavigationStack {
            Group {
                if let output {
                    ScrollView {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else if isRunning {
                    ProgressView()
                        .padding()
                } else {
                    hostPicker(snippet)
                }
            }
            .navigationTitle(Text(snippet.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { runningSnippet = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func hostPicker(_ snippet: SnippetRecord) -> some View {
        List {
            Section("snippets.chooseHost") {
                ForEach(manager.allHosts) { record in
                    Button("\(record.name) (\(record.username)@\(record.hostname))") {
                        run(snippet, on: record)
                    }
                }
            }
        }
    }

    private func run(_ snippet: SnippetRecord, on record: HostRecord) {
        isRunning = true
        output = nil
        Task {
            do {
                let (session, config) = try manager.openSession(for: record)
                try await session.connect(config: config, knownHosts: manager.knownHosts)
                manager.markConnected(record)
                let result = try await session.run(snippet.command)
                output = result.output
            } catch {
                errorMessage = error.localizedDescription
                runningSnippet = nil
            }
            isRunning = false
        }
    }
}
