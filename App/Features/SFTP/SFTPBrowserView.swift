import CoreSSH
import GlassKit
import Persistence
import SwiftUI
import UIKit

/// SFTP file browser (spec §4.4): single list + breadcrumb navigation, with
/// upload/download, rename/delete/move, permissions view and a built-in text
/// editor for files ≤ 1MB.
struct SFTPBrowserView: View {
    let record: HostRecord

    @Environment(HostManager.self) private var manager
    @State private var sftp: (any SFTPService)?
    @State private var entries: [SFTPEntry] = []
    @State private var currentPath = "/"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showUpload = false
    @State private var editingEntry: SFTPEntry?
    @State private var showEditor = false
    @State private var editorContent = ""
    @State private var editorPath = ""
    @State private var showRename = false
    @State private var renameTarget: SFTPEntry?
    @State private var renameText = ""

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if entries.isEmpty {
                ContentUnavailableView("sftp.empty", systemImage: "tray")
            } else {
                ForEach(entries, id: \.name) { entry in
                    row(for: entry)
                }
            }
        }
        .navigationTitle(Text(SFTPPath.displayName(of: currentPath)))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { breadcrumb }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("sftp.upload", systemImage: "square.and.arrow.up") {
                    showUpload = true
                }
                Menu {
                    Button("sftp.newFolder", systemImage: "folder.badge.plus") {
                        createFolder()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await open() }
        .fileImporter(
            isPresented: $showUpload,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: true
        ) { result in
            handleUpload(result)
        }
        .sheet(isPresented: $showEditor) {
            editorSheet
        }
        .alert(Text("sftp.rename.title"), isPresented: $showRename) {
            TextField("sftp.rename.prompt", text: $renameText)
            Button("common.cancel", role: .cancel) {}
            Button("common.save") { performRename() }
        }
        .alert(Text("error.title"), isPresented: .init(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GlassSpacing.xs) {
                crumb("sftp.root", path: "/")
                ForEach(breadcrumbSteps, id: \.path) { step in
                    Image(systemName: "chevron.right").font(.caption2)
                    crumb(String(step.label), path: step.path)
                }
            }
            .padding(.horizontal, GlassSpacing.md)
            .padding(.vertical, 6)
        }
        .background(.thinMaterial)
    }

    /// Precomputed breadcrumb steps (label + full path), so the view body has
    /// no mutable capture — cleaner for Swift 6/view builders and avoids a
    /// Release-only "failed to produce diagnostic" compiler quirk.
    private var breadcrumbSteps: [(label: Substring, path: String)] {
        let components = currentPath.split(separator: "/")
        var steps: [(label: Substring, path: String)] = []
        steps.reserveCapacity(components.count)
        var accumulated = "/"
        for component in components {
            accumulated = accumulated == "/" ? "/" + component : accumulated + "/" + component
            steps.append((label: component, path: accumulated))
        }
        return steps
    }

    private func crumb(_ label: String, path: String) -> some View {
        Button(label) {
            if path != currentPath {
                Task { await loadDirectory(path) }
            }
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .disabled(path == currentPath)
    }

    private func row(for entry: SFTPEntry) -> some View {
        Button {
            open(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: entry.kind))
                    .foregroundStyle(entry.kind == .directory ? Color.glassPrimaryText : Color.glassSecondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let size = entry.size, entry.kind != .directory {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        } else if entry.kind == .directory {
                            Text("sftp.permissions.folder")
                        }
                        if let permissions = entry.permissions {
                            Text(Self.permissionString(permissions))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.glassSecondaryText)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entry.kind != .directory {
                Button("sftp.edit", systemImage: "pencil") { openEditor(entry) }
                Button("sftp.download", systemImage: "square.and.arrow.down") { download(entry) }
            }
            Button("sftp.renamePrompt", systemImage: "pencil.circle") {
                renameTarget = entry
                renameText = entry.name
                showRename = true
            }
            Button("sftp.delete", systemImage: "trash", role: .destructive) { delete(entry) }
        }
        .accessibilityIdentifier("sftp.row.\(entry.name)")
    }

    private var editorSheet: some View {
        NavigationStack {
            TextEditor(text: $editorContent)
                .font(.system(.body, design: .monospaced))
                .navigationTitle(Text(SFTPPath.displayName(of: editorPath)))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { showEditor = false }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("common.save") { saveEditor() }
                    }
                }
        }
    }

    // MARK: - Actions

    private func open() async {
        if isLoading {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            if sftp == nil {
                let (freshSession, config) = try manager.openSession(for: record)
                try await freshSession.connect(config: config, knownHosts: manager.knownHosts)
                manager.markConnected(record)
                sftp = try await freshSession.openSFTP()
            }
            entries = try await sftp!.list(directory: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDirectory(_ path: String) async {
        currentPath = path
        await open()
    }

    private func open(_ entry: SFTPEntry) {
        switch entry.kind {
        case .directory:
            Task { await loadDirectory(SFTPPath.joining(currentPath, entry.name)) }
        case .file:
            openEditor(entry)
        default:
            break
        }
    }

    private func openEditor(_ entry: SFTPEntry) {
        let path = SFTPPath.joining(currentPath, entry.name)
        Task {
            guard let data = try? await sftp?.readFile(at: path), data.count <= 1_000_000 else {
                errorMessage = String(localized: "sftp.edit.tooLarge")
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                errorMessage = String(localized: "sftp.edit.notText")
                return
            }
            editorContent = text
            editorPath = path
            showEditor = true
        }
    }

    private func saveEditor() {
        guard let data = editorContent.data(using: .utf8) else { return }
        Task {
            do {
                _ = try await sftp?.writeFile(data: data, to: editorPath)
                showEditor = false
                await open()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performRename() {
        guard let renameTarget, !renameText.isEmpty else { return }
        let old = SFTPPath.joining(currentPath, renameTarget.name)
        let new = SFTPPath.joining(currentPath, renameText)
        Task {
            do {
                _ = try await sftp?.rename(from: old, to: new)
                showRename = false
                await open()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ entry: SFTPEntry) {
        let path = SFTPPath.joining(currentPath, entry.name)
        Task {
            do {
                _ = try await sftp?.delete(at: path, isDirectory: entry.kind == .directory)
                await open()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createFolder() {
        let alert = UIAlertController(title: String(localized: "sftp.newFolder"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = String(localized: "sftp.newFolderName")
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.save"), style: .default) { _ in
            guard let text = alert.textFields?.first?.text, !text.isEmpty else { return }
            Task {
                do {
                    _ = try await sftp?.createDirectory(at: SFTPPath.joining(currentPath, text))
                    await open()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        })
        // Present from the scene's root view controller.
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController
        {
            root.present(alert, animated: true)
        }
    }

    private func handleUpload(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        for url in urls {
            let secured = url.startAccessingSecurityScopedResource()
            defer {
                if secured {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: url) else { continue }
            let remote = SFTPPath.joining(currentPath, url.lastPathComponent)
            Task {
                do {
                    _ = try await sftp?.writeFile(data: data, to: remote)
                    await open()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func download(_ entry: SFTPEntry) {
        let path = SFTPPath.joining(currentPath, entry.name)
        Task {
            guard let data = try? await sftp?.readFile(at: path) else {
                errorMessage = String(localized: "sftp.download.failed")
                return
            }
            // Best-effort share sheet via the root controller; local state only.
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(entry.name)
            try? data.write(to: temp)
            let controller = UIActivityViewController(activityItems: [temp], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController
            {
                root.present(controller, animated: true)
            }
        }
    }

    private func icon(for kind: SFTPEntry.Kind) -> String {
        switch kind {
        case .directory: "folder"
        case .file: "doc"
        case .symlink: "link"
        case .unknown: "questionmark"
        }
    }

    /// Renders the Unix mode permission bits as `rwxrwxrwx`.
    static func permissionString(_ mode: UInt32) -> String {
        let masks: [(UInt32, String)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        return masks.map { pair in
            mode & pair.0 != 0 ? pair.1 : "-"
        }.joined()
    }
}
