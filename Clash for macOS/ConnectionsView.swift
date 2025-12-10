import SwiftUI

struct Connection: Identifiable {
    let id = UUID()
    let host: String
    let destinationIP: String
    let sourceIP: String
    let sourcePort: String
    let destinationPort: String
    let network: String
    let type: String
    let chain: [String]
    let rule: String
    let downloadSpeed: String
    let uploadSpeed: String
    let startTime: Date
    let download: String
    let upload: String
}

struct ConnectionsView: View {
    @State private var searchText = ""
    @State private var connections: [Connection] = [
        Connection(
            host: "google.com",
            destinationIP: "142.250.190.46",
            sourceIP: "127.0.0.1",
            sourcePort: "54321",
            destinationPort: "443",
            network: "TCP",
            type: "HTTPS",
            chain: ["Proxy", "HK Server"],
            rule: "Rule",
            downloadSpeed: "20 KB/s",
            uploadSpeed: "5 KB/s",
            startTime: Date(),
            download: "1.2 MB",
            upload: "50 KB"
        ),
        Connection(
            host: "github.com",
            destinationIP: "140.82.112.4",
            sourceIP: "127.0.0.1",
            sourcePort: "54123",
            destinationPort: "443",
            network: "TCP",
            type: "HTTPS",
            chain: ["Proxy", "US Server"],
            rule: "Rule",
            downloadSpeed: "0 KB/s",
            uploadSpeed: "0 KB/s",
            startTime: Date().addingTimeInterval(-60),
            download: "500 KB",
            upload: "200 KB"
        ),
        Connection(
            host: "api.twitter.com",
            destinationIP: "104.244.42.193",
            sourceIP: "127.0.0.1",
            sourcePort: "55678",
            destinationPort: "443",
            network: "TCP",
            type: "HTTPS",
            chain: ["Proxy", "SG Server"],
            rule: "Proxy",
            downloadSpeed: "100 KB/s",
            uploadSpeed: "20 KB/s",
            startTime: Date().addingTimeInterval(-120),
            download: "3.5 MB",
            upload: "150 KB"
        ),
        Connection(
            host: "baidu.com",
            destinationIP: "220.181.38.148",
            sourceIP: "127.0.0.1",
            sourcePort: "60001",
            destinationPort: "443",
            network: "TCP",
            type: "HTTPS",
            chain: ["Direct"],
            rule: "Direct",
            downloadSpeed: "5 KB/s",
            uploadSpeed: "1 KB/s",
            startTime: Date().addingTimeInterval(-300),
            download: "125 KB",
            upload: "10 KB"
        )
    ]
    
    var filteredConnections: [Connection] {
        if searchText.isEmpty {
            return connections
        } else {
            return connections.filter { $0.host.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var totalDownload: String {
        "5.3 MB"
    }
    
    var totalUpload: String {
        "410 KB"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            SettingsHeader(title: "Connections", subtitle: "Total Download: \(totalDownload)  Upload: \(totalUpload)") {
                ClearButton(title: "Close All") {
                    connections.removeAll()
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            
            SearchField(placeholder: "Search Host, IP...", text: $searchText)
                .padding(.horizontal, 30)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredConnections) { connection in
                        ConnectionRow(connection: connection) {
                            if let index = connections.firstIndex(where: { $0.id == connection.id }) {
                                connections.remove(at: index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
    }
}

struct ConnectionRow: View {
    let connection: Connection
    let onClose: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom) {
                    Text(connection.host)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    Text("\(connection.destinationIP):\(connection.destinationPort)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                
                HStack(spacing: 12) {
                    Label(connection.network, systemImage: "network")
                    Label(connection.chain.joined(separator: " -> "), systemImage: "arrow.triangle.branch")
                    Label(connection.rule, systemImage: "text.magnifyingglass")
                }
                .font(.caption2)
                .foregroundStyle(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(connection.downloadSpeed)
                        .foregroundStyle(.green)
                    Text(connection.uploadSpeed)
                        .foregroundStyle(.yellow)
                }
                .font(.system(size: 13))
                
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                        Text(connection.download)
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                        Text(connection.upload)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.gray)
            }
            .padding(.trailing, 10)
            
            if isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 16)
            }
        }
        .padding(12)
        .background(isHovered ? Color.primary.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    ConnectionsView()
}
