import SwiftUI

struct ProxiesView: View {
    @State private var selectedMode = "Rule"
    @State private var expandedGroups: Set<String> = ["Proxy", "Final"]
    
    let modes = ["Global", "Rule", "Direct", "Script"]
    
    var body: some View {
        VStack(spacing: 0) {
            VStack {
                SettingsHeader(title: "Proxies") {
                    HStack(spacing: 0) {
                        ForEach(modes, id: \.self) { mode in
                            Button(action: { selectedMode = mode }) {
                                Text(mode)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(selectedMode == mode ? Color.blue : Color.clear)
                                    .foregroundStyle(selectedMode == mode ? .white : .gray)
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
            
            ScrollView {
                VStack(spacing: 15) {
                    ProxyGroupView(title: "Proxy", type: "Select", selection: "US Server 1", proxies: [
                        "US Server 1": 150,
                        "US Server 2": 230,
                        "JP Server": 80,
                        "Auto": 0
                    ])
                    
                    ProxyGroupView(title: "PayPal", type: "URL Test", selection: "US Server 1", proxies: [
                        "US Server 1": 150,
                        "US Server 2": 230
                    ])
                    
                    ProxyGroupView(title: "Spotify", type: "Select", selection: "Direct", proxies: [
                        "Direct": 0,
                        "US Server 1": 150,
                        "Reject": 0
                    ])
                    
                    ProxyGroupView(title: "Final", type: "Select", selection: "Proxy", proxies: [
                        "Proxy": 0,
                        "Direct": 0,
                        "Reject": 0
                    ])
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
    }
}

struct ProxyGroupView: View {
    let title: String
    let type: String
    @State var selection: String
    let proxies: [String: Int]
    @State private var isExpanded = true
    
    var sortedProxies: [String] {
        return proxies.keys.sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(":: \(type)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Spacer()
                    Text(selection)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .padding(.trailing, 10)
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
                    ForEach(sortedProxies, id: \.self) { proxyName in
                        ProxyCard(
                            name: proxyName,
                            latency: proxies[proxyName] ?? 0,
                            isSelected: selection == proxyName,
                            action: { selection = proxyName }
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
                    if latency > 0 {
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
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProxiesView()
        .frame(width: 800, height: 600)
}
