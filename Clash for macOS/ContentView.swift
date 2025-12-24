import SwiftUI

struct ContentView: View {
    @Bindable private var navigationManager = NavigationManager.shared

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $navigationManager.selection)
        } detail: {
            switch navigationManager.selection {
            case .general:
                GeneralView()
            case .proxies:
                ProxiesView()
            case .profiles:
                ProfilesView()
            case .rules:
                RulesView()
            case .ruleProviders:
                RuleProvidersView()
            case .connections:
                ConnectionsView()
            case .logs:
                LogsView()
            case .settings:
                SettingsView()
            }
        }
        .preferredColorScheme(AppSettings.shared.appearance.colorScheme)
        .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
    }
}

#Preview {
    ContentView()
}
