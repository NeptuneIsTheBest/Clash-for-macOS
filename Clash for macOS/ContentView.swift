import SwiftUI

struct ContentView: View {
    @State private var selection: NavigationItem = .general
    private var dataService: ClashDataService { ClashDataService.shared }
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection {
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
        .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
        .onAppear {
            dataService.startMonitoring()
        }
        .onDisappear {
            dataService.stopMonitoring()
        }
    }
}

#Preview {
    ContentView()
}

