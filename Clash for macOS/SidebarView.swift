import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case general = "General"
    case proxies = "Proxies"
    case profiles = "Profiles"
    case rules = "Rules"
    case ruleProviders = "Rule Providers"
    case connections = "Connections"
    case logs = "Logs"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .general: return "house.fill"
        case .proxies: return "network"
        case .profiles: return "doc.text.fill"
        case .rules: return "checklist"
        case .ruleProviders: return "list.bullet.rectangle.portrait.fill"
        case .connections: return "arrow.up.arrow.down"
        case .logs: return "terminal.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: NavigationItem
    @Bindable private var settings = AppSettings.shared
    
    @State private var uploadSpeed: Int64 = 0
    @State private var downloadSpeed: Int64 = 0
    @State private var trafficTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clash for macOS")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding()
            .padding(.top, 10)
            
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(NavigationItem.allCases) { item in
                        Button(action: {
                            selection = item
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .frame(width: 20)
                                Text(item.rawValue)
                                    .font(.system(size: 14))
                                Spacer()
                                if selection == item {
                                    Rectangle()
                                        .frame(width: 3)
                                        .foregroundStyle(Color.blue)
                                }
                            }
                            .foregroundStyle(selection == item ? .primary : .secondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                            .background(
                                selection == item ? Color.primary.opacity(0.1) : Color.clear
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text(formatSpeed(uploadSpeed))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 12))
                    Text(formatSpeed(downloadSpeed))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            .onAppear {
                startMonitoring()
            }
            .onDisappear {
                stopMonitoring()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 200, maxWidth: 200)
    }
    
    private func startMonitoring() {
        trafficTask = Task {
            do {
                let stream = ClashAPI.shared.getTrafficStream()
                for try await traffic in stream {
                    await MainActor.run {
                        uploadSpeed = traffic.up
                        downloadSpeed = traffic.down
                    }
                }
            } catch {
            }
        }
    }
    
    private func stopMonitoring() {
        trafficTask?.cancel()
        trafficTask = nil
    }
    

}

#Preview {
    SidebarView(selection: .constant(.general))
}
