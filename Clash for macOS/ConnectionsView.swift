import SwiftUI
import Observation

@Observable
class ConnectionsViewModel {
    var connections: [ConnectionItem] = []
    var searchText = ""
    var totalDownload: Int64 = 0
    var totalUpload: Int64 = 0
    private var timer: Timer?
    private var lastUpdate: Date?
    private var previousTraffic: [String: (upload: Int64, download: Int64)] = [:]
    
    struct ConnectionItem: Identifiable {
        let id: String
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
    
    func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchConnections()
            }
        }
        Task { await fetchConnections() }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    func fetchConnections() async {
        do {
            let response = try await ClashAPI.shared.getConnections()
            let now = Date()
            let timeDelta = lastUpdate != nil ? now.timeIntervalSince(lastUpdate!) : 1.0
            
            await MainActor.run {
                self.totalDownload = response.downloadTotal
                self.totalUpload = response.uploadTotal
                
                self.connections = response.connections.map { conn in
                    let prev = previousTraffic[conn.id]
                    let uploadSpeedBytes = prev != nil ? Double(conn.upload - prev!.upload) / timeDelta : 0
                    let downloadSpeedBytes = prev != nil ? Double(conn.download - prev!.download) / timeDelta : 0
                    
                    // Update cache
                    previousTraffic[conn.id] = (conn.upload, conn.download)
                    
                    let host = conn.metadata.host.isEmpty ? (conn.metadata.destinationIP ?? "Unknown") : conn.metadata.host
                    let destIP = conn.metadata.destinationIP ?? ""
                    let destPort = conn.metadata.destinationPort ?? ""
                    
                    // Parse start time
                    // Clash usually returns RFC3339 format, but we'll try a flexible approach or just use ISO8601
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let startDate = formatter.date(from: conn.start) ?? Date()
                    
                    return ConnectionItem(
                        id: conn.id,
                        host: host,
                        destinationIP: destIP,
                        sourceIP: conn.metadata.sourceIP,
                        sourcePort: conn.metadata.sourcePort,
                        destinationPort: destPort,
                        network: conn.metadata.network,
                        type: conn.metadata.type,
                        chain: conn.chains,
                        rule: conn.rule,
                        downloadSpeed: ByteUtils.format(Int64(downloadSpeedBytes)) + "/s",
                        uploadSpeed: ByteUtils.format(Int64(uploadSpeedBytes)) + "/s",
                        startTime: startDate,
                        download: ByteUtils.format(conn.download),
                        upload: ByteUtils.format(conn.upload)
                    )
                }.sorted(by: { $0.startTime > $1.startTime })
                
                // Cleanup old connections from cache
                let currentIds = Set(response.connections.map { $0.id })
                let oldIds = Set(previousTraffic.keys)
                for id in oldIds.subtracting(currentIds) {
                    previousTraffic.removeValue(forKey: id)
                }
                
                lastUpdate = now
            }
        } catch {
            print("Failed to fetch connections: \(error)")
        }
    }
    
    func closeConnection(id: String) async {
        do {
            try await ClashAPI.shared.closeConnection(id: id)
            // Remove locally to feel instant
            await MainActor.run {
                if let index = connections.firstIndex(where: { $0.id == id }) {
                    connections.remove(at: index)
                }
            }
        } catch {
            print("Failed to close connection: \(error)")
        }
    }
    
    func closeAllConnections() async {
        do {
            try await ClashAPI.shared.closeAllConnections()
            await MainActor.run {
                connections.removeAll()
            }
        } catch {
            print("Failed to close all connections: \(error)")
        }
    }
}

struct ByteUtils {
    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
}

struct ConnectionsView: View {
    @State private var viewModel = ConnectionsViewModel()
    
    var filteredConnections: [ConnectionsViewModel.ConnectionItem] {
        if viewModel.searchText.isEmpty {
            return viewModel.connections
        } else {
            return viewModel.connections.filter {
                $0.host.localizedCaseInsensitiveContains(viewModel.searchText) ||
                $0.destinationIP.localizedCaseInsensitiveContains(viewModel.searchText) ||
                $0.rule.localizedCaseInsensitiveContains(viewModel.searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            SettingsHeader(title: "Connections", subtitle: "Total Download: \(ByteUtils.format(viewModel.totalDownload))  Upload: \(ByteUtils.format(viewModel.totalUpload))") {
                ClearButton(title: "Close All") {
                    Task {
                        await viewModel.closeAllConnections()
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            
            SearchField(placeholder: "Search Host, IP, Rule...", text: $viewModel.searchText)
                .padding(.horizontal, 30)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredConnections) { connection in
                        ConnectionRow(connection: connection) {
                            Task {
                                await viewModel.closeConnection(id: connection.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}

struct ConnectionRow: View {
    let connection: ConnectionsViewModel.ConnectionItem
    let onClose: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom) {
                    Text(connection.host)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
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
