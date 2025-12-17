import SwiftUI
import Observation

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case silent = "SILENT"
    
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .silent: return .secondary
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

struct ClashLogMessage: Codable {
    let type: String
    let payload: String
}

@Observable
class LogViewModel {
    var logs: [LogEntry] = []
    var isStreaming = false
    private var streamTask: Task<Void, Never>?
    
    func startStreaming() {
        guard !isStreaming else { return }
        isStreaming = true
        
        streamTask = Task { @MainActor in
            do {
                let stream = ClashAPI.shared.getLogsStream()
                for try await line in stream {
                    if let data = line.data(using: .utf8),
                       let message = try? JSONDecoder().decode(ClashLogMessage.self, from: data) {
                        
                        let levelString = message.type.uppercased()
                        let level = LogLevel(rawValue: levelString) ?? .info
                        
                        let (type, payload) = parsePayload(message.payload)
                        
                        let entry = LogEntry(
                            timestamp: Date(),
                            level: level,
                            type: type,
                            payload: payload
                        )
                        
                        logs.insert(entry, at: 0)
                        
                        if logs.count > 1000 {
                            logs.removeLast()
                        }
                    }
                }
            } catch {
                print("Log stream error: \(error)")
                isStreaming = false
            }
        }
    }
    
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
    
    func clear() {
        logs.removeAll()
    }
    
    private func parsePayload(_ payload: String) -> (String, String) {
        if payload.hasPrefix("[") {
            if let endIndex = payload.firstIndex(of: "]") {
                let typeStart = payload.index(after: payload.startIndex)
                let type = String(payload[typeStart..<endIndex])
                let contentStart = payload.index(after: endIndex)
                let content = String(payload[contentStart...]).trimmingCharacters(in: .whitespaces)
                return (type, content)
            }
        }
        return ("Core", payload)
    }
}

struct LogsView: View {
    @State private var viewModel = LogViewModel()
    @State private var searchText = ""
    @State private var selectedLevel: LogLevel? = nil
    
    var filteredLogs: [LogEntry] {
        viewModel.logs.filter { log in
            let matchesSearch = searchText.isEmpty || 
                log.payload.localizedCaseInsensitiveContains(searchText) ||
                log.type.localizedCaseInsensitiveContains(searchText)
            let matchesLevel = selectedLevel == nil || log.level == selectedLevel
            return matchesSearch && matchesLevel
        }
    }
    
    
    var body: some View {
        VStack(spacing: 20) {
            SettingsHeader(title: "Logs", subtitle: "\(viewModel.logs.count) entries") {
                HStack {
                    if viewModel.isStreaming {
                        Button(action: { viewModel.stopStreaming() }) {
                            Image(systemName: "pause.circle")
                        }
                        .help("Pause Logs")
                    } else {
                        Button(action: { viewModel.startStreaming() }) {
                            Image(systemName: "play.circle")
                        }
                        .help("Resume Logs")
                    }
                    
                    ClearButton(title: "Clear") {
                        viewModel.clear()
                    }
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
        .onAppear {
            viewModel.startStreaming()
        }
        .onDisappear {
            viewModel.stopStreaming()
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
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovered ? Color.primary.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    LogsView()
}
