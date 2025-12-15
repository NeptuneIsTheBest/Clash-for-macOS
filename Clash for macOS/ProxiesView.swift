import SwiftUI
import Observation

@Observable
class ProxiesViewModel {
    var proxyGroups: [ProxyGroup] = []
    var allProxies: [String: ClashAPI.ProxyNode] = [:]
    var proxyMode: String = "rule"
    var isLoading = false
    var delays: [String: Int] = [:]
    var testingProxies: Set<String> = []
    
    struct ProxyGroup: Identifiable {
        var id: String { name }
        let name: String
        let type: String
        let now: String?
        let all: [String]
    }
    
    func loadProxies() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let proxies = try await ClashAPI.shared.getProxies()
            await MainActor.run {
                self.allProxies = proxies
                self.proxyGroups = proxies.values
                    .filter { isProxyGroup($0.type) }
                    .sorted { $0.name < $1.name }
                    .map { ProxyGroup(name: $0.name, type: $0.type, now: $0.now, all: $0.all ?? []) }
                
                for (name, node) in proxies {
                    if let history = node.history, let last = history.last, last.delay > 0 {
                        self.delays[name] = last.delay
                    }
                }
            }
        } catch {
            print("Failed to load proxies: \(error)")
        }
    }
    
    func loadMode() async {
        do {
            let configs = try await ClashAPI.shared.getConfigs()
            if case .string(let mode) = configs["mode"] {
                await MainActor.run {
                    self.proxyMode = mode.lowercased()
                }
            }
        } catch {
            print("Failed to load mode: \(error)")
        }
    }
    
    func setMode(_ mode: String) async {
        do {
            try await ClashAPI.shared.updateConfigs(params: ["mode": mode.lowercased()])
            await MainActor.run {
                self.proxyMode = mode.lowercased()
            }
        } catch {
            print("Failed to set mode: \(error)")
        }
    }
    
    func selectProxy(group: String, proxy: String) async {
        do {
            try await ClashAPI.shared.selectProxy(selectorName: group, proxyName: proxy)
            await loadProxies()
        } catch {
            print("Failed to select proxy: \(error)")
        }
    }
    
    func testDelay(proxyName: String) async {
        await MainActor.run {
            testingProxies.insert(proxyName)
        }
        
        do {
            let delay = try await ClashAPI.shared.getProxyDelay(name: proxyName)
            await MainActor.run {
                self.delays[proxyName] = delay
                self.testingProxies.remove(proxyName)
            }
        } catch {
            await MainActor.run {
                self.delays[proxyName] = 0
                self.testingProxies.remove(proxyName)
            }
        }
    }
    
    func testGroupDelay(groupName: String) async {
        guard let group = proxyGroups.first(where: { $0.name == groupName }) else { return }
        
        await MainActor.run {
            for proxy in group.all {
                testingProxies.insert(proxy)
            }
        }
        
        do {
            let delays = try await ClashAPI.shared.getGroupDelay(name: groupName)
            await MainActor.run {
                for (name, delay) in delays {
                    self.delays[name] = delay
                }
                for proxy in group.all {
                    self.testingProxies.remove(proxy)
                }
            }
        } catch {
            await MainActor.run {
                for proxy in group.all {
                    self.testingProxies.remove(proxy)
                }
            }
        }
    }
    
    private func isProxyGroup(_ type: String) -> Bool {
        ["Selector", "URLTest", "Fallback", "LoadBalance", "Relay"].contains(type)
    }
}

struct ProxiesView: View {
    @State private var viewModel = ProxiesViewModel()
    
    let modes = ["Global", "Rule", "Direct"]
    
    var filteredProxyGroups: [ProxiesViewModel.ProxyGroup] {
        switch viewModel.proxyMode {
        case "global":
            return viewModel.proxyGroups.filter { $0.name == "GLOBAL" }
        case "direct":
            return []
        default:
            return viewModel.proxyGroups.filter { $0.name != "GLOBAL" }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack {
                SettingsHeader(title: "Proxies") {
                    HStack(spacing: 0) {
                        ForEach(modes, id: \.self) { mode in
                            Button(action: {
                                Task {
                                    await viewModel.setMode(mode)
                                }
                            }) {
                                Text(mode)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(viewModel.proxyMode == mode.lowercased() ? Color.blue : Color.clear)
                                    .foregroundStyle(viewModel.proxyMode == mode.lowercased() ? .white : .gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 20)
            
            if filteredProxyGroups.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    if viewModel.proxyMode == "direct" {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text("Direct mode enabled")
                            .foregroundStyle(.gray)
                        Text("All traffic will be sent directly without proxy")
                            .font(.caption)
                            .foregroundStyle(.gray.opacity(0.7))
                    } else {
                        Image(systemName: "network.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text("No proxy groups available")
                            .foregroundStyle(.gray)
                        Text("Make sure Clash core is running")
                            .font(.caption)
                            .foregroundStyle(.gray.opacity(0.7))
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(filteredProxyGroups) { group in
                            ProxyGroupView(
                                group: group,
                                delays: viewModel.delays,
                                testingProxies: viewModel.testingProxies,
                                onSelect: { proxy in
                                    Task {
                                        await viewModel.selectProxy(group: group.name, proxy: proxy)
                                    }
                                },
                                onTestGroup: {
                                    Task {
                                        await viewModel.testGroupDelay(groupName: group.name)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            }
        }
        .task {
            await viewModel.loadMode()
            await viewModel.loadProxies()
        }
        .onChange(of: ClashCoreManager.shared.isRunning) { _, isRunning in
            if isRunning {
                Task {
                    await viewModel.loadMode()
                    await viewModel.loadProxies()
                }
            }
        }
    }
}

struct ProxyGroupView: View {
    let group: ProxiesViewModel.ProxyGroup
    let delays: [String: Int]
    let testingProxies: Set<String>
    let onSelect: (String) -> Void
    let onTestGroup: () -> Void
    @State private var isExpanded = true
    
    private var isSelectable: Bool {
        group.type == "Selector"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(":: \(group.type)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Spacer()
                    
                    Button(action: onTestGroup) {
                        Image(systemName: "bolt")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    
                    if let now = group.now {
                        Text(now)
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                            .padding(.trailing, 10)
                    }
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.gray)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(group.all, id: \.self) { proxyName in
                        ProxyCard(
                            name: proxyName,
                            latency: delays[proxyName] ?? 0,
                            isSelected: group.now == proxyName,
                            isTesting: testingProxies.contains(proxyName),
                            isSelectable: isSelectable,
                            action: {
                                if isSelectable {
                                    onSelect(proxyName)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 5)
            }
        }
    }
}

struct ProxyCard: View {
    let name: String
    let latency: Int
    let isSelected: Bool
    var isTesting: Bool = false
    var isSelectable: Bool = true
    let action: () -> Void
    
    var latencyColor: Color {
        if isSelected { return .white }
        if latency == 0 { return .gray }
        if latency < 200 { return .green }
        if latency < 500 { return .orange }
        return .red
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .primary)
                
                HStack {
                    if isTesting {
                        ProgressView()
                            .controlSize(.mini)
                    } else if latency > 0 {
                        Text("\(latency) ms")
                            .font(.caption2)
                            .foregroundStyle(latencyColor)
                    } else {
                        Text("---")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                }
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.8) : Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .opacity(isSelectable ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
    }
}

#Preview {
    ProxiesView()
        .frame(width: 800, height: 600)
}
