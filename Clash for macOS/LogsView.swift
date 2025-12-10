import SwiftUI

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let type: String
    let payload: String
}

struct LogsView: View {
    @State private var searchText = ""
    @State private var selectedLevel: LogLevel? = nil
    @State private var logs: [LogEntry] = [
        LogEntry(timestamp: Date(), level: .info, type: "dns", payload: "Resolved google.com to 142.250.190.46"),
        LogEntry(timestamp: Date().addingTimeInterval(-5), level: .info, type: "proxy", payload: "Matched rule DOMAIN-SUFFIX,google.com using Proxy"),
        LogEntry(timestamp: Date().addingTimeInterval(-10), level: .debug, type: "tcp", payload: "Connection established to 142.250.190.46:443"),
        LogEntry(timestamp: Date().addingTimeInterval(-15), level: .warning, type: "dns", payload: "DNS query timeout for api.example.com"),
        LogEntry(timestamp: Date().addingTimeInterval(-20), level: .error, type: "proxy", payload: "Failed to connect to proxy server: connection refused"),
        LogEntry(timestamp: Date().addingTimeInterval(-25), level: .info, type: "rule", payload: "Matched GEOIP,CN using Direct"),
        LogEntry(timestamp: Date().addingTimeInterval(-30), level: .debug, type: "tcp", payload: "Connection closed: github.com:443"),
        LogEntry(timestamp: Date().addingTimeInterval(-35), level: .info, type: "dns", payload: "Resolved twitter.com to 104.244.42.193"),
        LogEntry(timestamp: Date().addingTimeInterval(-40), level: .info, type: "proxy", payload: "Matched rule DOMAIN-KEYWORD,twitter using Proxy"),
        LogEntry(timestamp: Date().addingTimeInterval(-45), level: .warning, type: "proxy", payload: "High latency detected on HK Server: 350ms"),
        LogEntry(timestamp: Date().addingTimeInterval(-50), level: .info, type: "rule", payload: "Matched DOMAIN-SUFFIX,baidu.com using Direct"),
        LogEntry(timestamp: Date().addingTimeInterval(-55), level: .debug, type: "udp", payload: "UDP session started: 8.8.8.8:53"),
    ]
    
    var filteredLogs: [LogEntry] {
        logs.filter { log in
            let matchesSearch = searchText.isEmpty || 
                log.payload.localizedCaseInsensitiveContains(searchText) ||
                log.type.localizedCaseInsensitiveContains(searchText)
            let matchesLevel = selectedLevel == nil || log.level == selectedLevel
            return matchesSearch && matchesLevel
        }
    }
    
    
    var body: some View {
        VStack(spacing: 20) {
            SettingsHeader(title: "Logs", subtitle: "\(logs.count) entries") {
                ClearButton(title: "Clear") {
                    logs.removeAll()
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            
            HStack(spacing: 12) {
                SearchField(placeholder: "Search logs...", text: $searchText)
                
                HStack(spacing: 6) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Button(action: {
                            if selectedLevel == level {
                                selectedLevel = nil
                            } else {
                                selectedLevel = level
                            }
                        }) {
                            Text(level.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(selectedLevel == level ? level.color.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
                                .foregroundStyle(selectedLevel == level ? level.color : .gray)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 30)
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredLogs) { log in
                        LogRow(log: log)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
    }
}

struct LogRow: View {
    let log: LogEntry
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(DateFormatters.shortTime.string(from: log.timestamp))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.gray)
                .frame(width: 90, alignment: .leading)
            
            Text(log.level.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(log.level.color.opacity(0.2))
                .foregroundStyle(log.level.color)
                .cornerRadius(4)
                .frame(width: 70)
            
            Text(log.type)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.cyan)
                .frame(width: 50, alignment: .leading)
            
            Text(log.payload)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovered ? Color.primary.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    LogsView()
}
