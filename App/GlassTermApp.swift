import CoreSSH
import Persistence
import SwiftUI

@main
struct GlassTermApp: App {
    private let container: ModelContainer
    private let hostManager: HostManager

    init() {
        var built = try? HostStore.makeContainer()
        if built == nil {
            built = try? HostStore.makeContainer(inMemory: true)
        }
        guard let container else {
            // SwiftData is an OS framework; reaching here means the device storage
            // layer itself is broken. An explicit, immediate failure beats a
            // silently data-less app.
            preconditionFailure("SwiftData container unavailable")
        }
        self.container = container

        let knownHosts = (try? KnownHostsStore()) ?? KnownHostsStore(storeURL: nil)
        self.hostManager = HostManager(
            hostStore: HostStore(container: container),
            secrets: KeychainStore(),
            knownHosts: knownHosts
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(hostManager)
                .modelContainer(container)
        }
    }
}
