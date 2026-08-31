import GlassKit
import Persistence
import SwiftUI
import UniformTypeIdentifiers

/// Create-or-edit host form. Secrets are handed to `HostManager` which stores
/// them exclusively in the Keychain.
struct AddEditHostView: View {
    @Environment(HostManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    let existing: HostRecord?

    @State private var name = ""
    @State private var hostname = ""
    @State private var portText = "22"
    @State private var username = ""
    @State private var group = ""
    @State private var authKind: HostAuthKind = .password
    @State private var password = ""
    @State private var keyPEM = ""
    @State private var keyFileName: String?
    @State private var passphrase = ""
    @State private var showKeyImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            GlassEffectContainer(spacing: GlassSpacing.md) {
                ScrollView {
                    VStack(spacing: GlassSpacing.md) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: GlassSpacing.md) {
                                fieldLabel("host.name")
                                TextField(Text("host.name.placeholder"), text: $name)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("host.field.name")

                                fieldLabel("host.address")
                                TextField(Text("host.address.placeholder"), text: $hostname)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("host.field.address")

                                fieldLabel("host.port")
                                TextField(Text("host.port.placeholder"), text: $portText)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.numberPad)

                                fieldLabel("host.username")
                                TextField(Text("host.username.placeholder"), text: $username)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()

                                fieldLabel("host.group")
                                TextField(Text("host.group.placeholder"), text: $group)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: GlassSpacing.md) {
                                fieldLabel("host.auth.method")
                                Picker(Text("host.auth.method"), selection: $authKind) {
                                    Text("host.auth.password").tag(HostAuthKind.password)
                                    Text("host.auth.key").tag(HostAuthKind.privateKey)
                                }
                                .pickerStyle(.segmented)

                                switch authKind {
                                case .password:
                                    SecureField(Text("host.auth.password.placeholder"), text: $password)
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityIdentifier("host.field.password")
                                case .privateKey:
                                    keySection
                                }
                            }
                        }

                        GlassButton("common.save", role: .prominent) { save() }
                            .disabled(!inputIsValid)
                    }
                    .padding(GlassSpacing.lg)
                }
            }
            .navigationTitle(Text(existing == nil ? "host.add" : "common.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassButton("common.cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showKeyImporter,
                allowedContentTypes: [.data, .text],
                allowsMultipleSelection: false
            ) { result in
                importKey(result)
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
                Button(Text("common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { prefillIfNeeded() }
        }
    }

    private func prefillIfNeeded() {
        guard let existing else { return }
        name = existing.name
        hostname = existing.hostname
        portText = String(existing.port)
        username = existing.username
        group = existing.group ?? ""
        authKind = existing.authKind
    }

    @ViewBuilder
    private var keySection: some View {
        GlassButton("host.auth.importKey", systemImage: "doc.badge.plus") {
            showKeyImporter = true
        }
        if let keyFileName {
            Label(keyFileName, systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(Color.glassSecondaryText)
        }
        SecureField(Text("host.auth.passphrase.placeholder"), text: $passphrase)
            .textFieldStyle(.roundedBorder)
    }

    private var inputIsValid: Bool {
        let secretReady = authKind == .password ? !password.isEmpty : !keyPEM.isEmpty
        let portValid = (Int(portText) ?? 0) > 0
        let secretAvailable = secretReady || existing?.secretRef != nil
        return !name.isEmpty && !hostname.isEmpty && !username.isEmpty && portValid && secretAvailable
    }

    private func fieldLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(Color.glassSecondaryText)
    }

    private func importKey(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let raw = try Data(contentsOf: url)
            guard let pem = String(data: raw, encoding: .utf8), pem.contains("PRIVATE KEY") else {
                errorMessage = String(localized: "host.auth.key.invalid")
                return
            }
            keyPEM = pem
            keyFileName = url.lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let port = Int(portText), port > 0, port <= 65535 else {
            errorMessage = String(localized: "host.port.invalid")
            return
        }
        let draft = HostManager.HostDraft(
            name: name,
            hostname: hostname,
            port: port,
            username: username,
            group: group,
            authKind: authKind,
            secret: authKind == .password ? password : keyPEM,
            passphrase: authKind == .privateKey ? passphrase : nil
        )
        do {
            _ = try manager.save(draft: draft, existing: existing)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
