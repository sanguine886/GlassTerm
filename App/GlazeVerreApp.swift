import CoreSSH
import Persistence
import SwiftData
import SwiftUI

@main
struct GlazeVerreApp: App {
    private let container: ModelContainer
    private let hostManager: HostManager
    private let snippetManager: SnippetManager
    private let providerManager: AIProviderManager
    private let chatManager: ChatManager
    private let auditManager: AuditManager

    init() {
        // One shared container covers every SwiftData model the app persists
        // (spec §4.1 hosts / §4.3 snippets / §4.5 AI providers + chats / §4.6 audit).
        guard let built = AppModelContainer.make() else {
            // SwiftData is an OS framework; reaching here means the device storage
            // layer itself is broken. An explicit, immediate failure beats a
            // silently data-less app.
            preconditionFailure("SwiftData container unavailable")
        }
        container = built

        let knownHosts = (try? KnownHostsStore()) ?? KnownHostsStore(storeURL: nil)
        hostManager = HostManager(
            hostStore: HostStore(container: built),
            secrets: KeychainStore(),
            knownHosts: knownHosts
        )
        snippetManager = SnippetManager(store: SnippetStore(container: built))
        providerManager = AIProviderManager(
            providerStore: AIProviderStore(container: built),
            secrets: KeychainStore()
        )
        chatManager = ChatManager(chatStore: ChatSessionStore(container: built))
        auditManager = AuditManager(auditStore: AuditStore(container: built))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(hostManager)
                .environment(snippetManager)
                .environment(providerManager)
                .environment(chatManager)
                .environment(auditManager)
                .modelContainer(container)
        }
    }
}

/// Constructs the app-wide SwiftData container. Each store exposes its own
/// `makeContainer` (per-store unit tests), but the app needs ONE container that
/// knows every model so a single `.modelContainer` injects them all.
private enum AppModelContainer {
    static func make() -> ModelContainer? {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        return try? ModelContainer(
            for:
            HostRecord.self,
            SnippetRecord.self,
            AIProviderRecord.self,
            ChatSessionRecord.self,
            AuditRecord.self,
            configurations: configuration
        )
    }
}
