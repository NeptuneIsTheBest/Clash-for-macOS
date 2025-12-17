import SwiftUI

struct ContentView: View {
    @State private var selection: NavigationItem = .general
    private var dataService: ClashDataService { ClashDataService.shared }
    
    var body: some View {
        HSplitView {
            SidebarView(selection: $selection)
            
            Group {
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
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
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

