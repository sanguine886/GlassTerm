import CoreSSH
import Persistence
import SwiftData
import SwiftUI

@main
struct GlassTermApp: App {
    private let container: ModelContainer
    private let hostManager: HostManager
    private let snippetManager: SnippetManager

    init() {
        guard let built = (try? HostStore.makeContainer()) ?? (try? HostStore.makeContainer(inMemory: true)) else {
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
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(hostManager)
                .environment(snippetManager)
                .modelContainer(container)
        }
    }
}
