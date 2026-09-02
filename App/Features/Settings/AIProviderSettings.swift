import AIAgent
import GlassKit
import Persistence
import SwiftUI

/// Provider management section inside Settings (spec §4.5). Lists configured
/// providers, switches the active default, and opens the edit form.
struct ProvidersSettingsSection: View {
    @Environment(AIProviderManager.self) private var manager
    @State private var editing: AIProviderRecord?
    @State private var showNew = false
    @State private var testResult: (UUID, String)?
    @State private var discovered: [String] = []

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: GlassSpacing.md) {
                Label("ai.settings.heading", systemImage: "brain.head.profile")
                    .font(.headline)
                    .foregroundStyle(Color.glassPrimaryText)

                if manager.providers.isEmpty {
                    Text("ai.settings.empty")
                        .font(.subheadline)
                        .foregroundStyle(Color.glassSecondaryText)
                } else {
                    providerRows
                }

                HStack {
                    GlassButton("ai.settings.new", systemImage: "plus", action: { showNew = true })
                    Spacer()
                }
            }
            .padding(.vertical, GlassSpacing.xs)
        }
        .sheet(item: $editing) { record in
            AIProviderEditView(record: record)
        }
        .sheet(isPresented: $showNew) {
            AIProviderEditView(record: nil)
        }
        .task { manager.refresh() }
    }

    private var providerRows: some View {
        ForEach(manager.providers) { provider in
            HStack(spacing: GlassSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.body)
                            .foregroundStyle(Color.glassPrimaryText)
                        if provider.id == manager.activeProviderID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.glassAccent)
                                .accessibilityLabel("ai.settings.active")
                        }
                    }
                    Text("\(provider.kindRaw) · \(provider.model)")
                        .font(.caption)
                        .foregroundStyle(Color.glassSecondaryText)
                }
                Spacer()
                Menu {
                    Button("ai.settings.discover", systemImage: "list.bullet.rectangle") {
                        discoverModels(provider)
                    }
                    if provider.id != manager.activeProviderID {
                        Button("ai.settings.useAsActive", systemImage: "checkmark") {
                            manager.setActive(provider.id)
                        }
                    }
                    Button("common.delete", systemImage: "trash", role: .destructive) {
                        manager.delete(provider)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.glassSecondaryText)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func discoverModels(_ provider: AIProviderRecord) {
        Task {
            let models = await manager.discoverModels(id: provider.id)
            if let models, !models.isEmpty {
                discovered = models
            } else {
                testResult = (provider.id, String(localized: "ai.settings.noDiscovery"))
            }
        }
    }
}

/// Edit / create form for an AI provider (spec §4.5).
struct AIProviderEditView: View {
    @Environment(AIProviderManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    /// The provider being edited, or nil for a new one.
    let record: AIProviderRecord?

    @State private var name = ""
    @State private var kindRaw = AIProviderKind.openAICompatible.rawValue
    @State private var baseURL = ""
    @State private var model = ""
    @State private var temperature = 0.2
    @State private var apiKey = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("ai.form.general") {
                    TextField("ai.form.name", text: $name)
                    Picker("ai.form.kind", selection: $kindRaw) {
                        ForEach(AIProviderKind.allKinds, id: \.rawValue) { kind in
                            Text(kind.displayName).tag(kind.rawValue)
                        }
                    }
                    TextField("ai.form.baseURL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("ai.form.model", text: $model)
                        .textInputAutocapitalization(.never)
                    HStack {
                        Text("ai.form.temperature")
                        Spacer()
                        Text(String(format: "%.1f", temperature))
                        Stepper("", value: $temperature, in: 0 ... 1.0, step: 0.1)
                            .labelsHidden()
                    }
                }
                Section("ai.form.key") {
                    SecureField("ai.form.apiKey", text: $apiKey)
                    Text("ai.form.keyHint")
                        .font(.caption)
                        .foregroundStyle(Color.glassSecondaryText)
                }

                if record != nil {
                    Section {
                        Button("ai.form.test", systemImage: "bolt.circle") {
                            testConnection()
                        }
                    }
                }
            }
            .navigationTitle(Text(record == nil ? "ai.form.newTitle" : "ai.form.editTitle"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(name.isEmpty || baseURL.isEmpty || model.isEmpty)
                }
            }
            .onAppear(perform: prefill)
            .alert(Text("error.title"), isPresented: .init(get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            })) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func prefill() {
        guard let record else { return }
        name = record.name
        kindRaw = record.kindRaw
        baseURL = record.baseURL
        model = record.model
        temperature = record.temperature
        apiKey = "" // Keychain value is never prefilled (spec §6.3.1)
    }

    private func save() {
        do {
            try manager.save(
                id: record?.id,
                name: name,
                kind: AIProviderKind(rawValue: kindRaw) ?? .openAICompatible,
                baseURL: baseURL,
                model: model,
                temperature: temperature,
                apiKey: apiKey
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func testConnection() {
        guard let id = record?.id else { return }
        Task {
            if let error = await manager.testConnection(id: id) {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}

extension AIProviderKind {
    /// All supported kinds, for the picker.
    static var allKinds: [AIProviderKind] {
        [.openAICompatible, .anthropic, .gemini]
    }

    /// Localized display name.
    var displayName: String {
        switch self {
        case .openAICompatible:
            String(localized: "ai.kind.openai")
        case .anthropic:
            String(localized: "ai.kind.anthropic")
        case .gemini:
            String(localized: "ai.kind.gemini")
        }
    }
}
