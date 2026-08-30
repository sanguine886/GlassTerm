import SwiftUI

/// Root tab scaffold (spec P0: 服务器 / 终端 / AI / 设置).
/// The system tab bar is Liquid Glass on iOS 26 by default.
struct RootTabView: View {
    var body: some View {
        TabView {
            ServersView()
                .tabItem { Label("tab.servers", systemImage: "server.rack") }
            TerminalSessionsView()
                .tabItem { Label("tab.terminal", systemImage: "terminal") }
            AssistantView()
                .tabItem { Label("tab.assistant", systemImage: "sparkles") }
            SettingsView()
                .tabItem { Label("tab.settings", systemImage: "gearshape") }
        }
    }
}
