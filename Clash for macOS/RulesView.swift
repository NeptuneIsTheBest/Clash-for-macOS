import SwiftUI

struct ClashRule: Identifiable, Hashable {
    let id = UUID()
    let type: String
    let payload: String
    let proxy: String
    let index: Int
}

@Observable
class RulesManager {
    static let shared = RulesManager()
    
    var rules: [ClashRule] = []
    var isLoading = false
    var errorMessage: String?
    
    private init() {}
    
    func fetchRules() async {
        isLoading = true
        errorMessage = nil
        
        let settings = AppSettings.shared
        let baseURL = "http://\(settings.externalController)"
        
        guard let url = URL(string: "\(baseURL)/rules") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if !settings.secret.isEmpty {
            request.setValue("Bearer \(settings.secret)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(RulesResponse.self, from: data)
            
            rules = response.rules.enumerated().map { index, rule in
                ClashRule(
                    type: rule.type,
                    payload: rule.payload,
                    proxy: rule.proxy,
                    index: index + 1
                )
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

struct RulesResponse: Codable {
    let rules: [RuleItem]
    
    struct RuleItem: Codable {
        let type: String
        let payload: String
        let proxy: String
    }
}

struct RulesView: View {
    @Bindable private var rulesManager = RulesManager.shared
    @State private var searchText = ""
    @State private var selectedType: String? = nil
    
    var filteredRules: [ClashRule] {
        var result = rulesManager.rules
        
        if let type = selectedType {
            result = result.filter { $0.type == type }
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.payload.localizedCaseInsensitiveContains(searchText) ||
                $0.proxy.localizedCaseInsensitiveContains(searchText) ||
                $0.type.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result
    }
    
    var ruleTypes: [String] {
        Array(Set(rulesManager.rules.map { $0.type })).sorted()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack {
                SettingsHeader(title: "Rules", subtitle: "\(rulesManager.rules.count) rules loaded") {
                    
                }
                
                HStack(spacing: 12) {
                    SearchField(placeholder: "Search rules...", text: $searchText)
                    
                    Picker("Type", selection: $selectedType) {
                        Text("All Types").tag(nil as String?)
                        ForEach(ruleTypes, id: \.self) { type in
                            Text(type).tag(type as String?)
                        }
                    }
                    .frame(width: 150)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 15)
            
            if rulesManager.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading rules...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer()
            } else if let error = rulesManager.errorMessage {
                Spacer()
                VStack(spacing: 15) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("Failed to load rules")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await rulesManager.fetchRules() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                Spacer()
            } else if rulesManager.rules.isEmpty {
                Spacer()
                VStack(spacing: 15) {
                    Image(systemName: "checklist")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    Text("No Rules")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Start Clash core and click refresh to load rules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Load Rules") {
                        Task { await rulesManager.fetchRules() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else {
                RulesTableView(rules: filteredRules)
            }
        }
        .task {
            if rulesManager.rules.isEmpty {
                await rulesManager.fetchRules()
            }
        }
        .onChange(of: ClashCoreManager.shared.isRunning) { _, isRunning in
            if isRunning {
                Task { await rulesManager.fetchRules() }
            }
        }
    }
}

struct RulesTableView: View {
    let rules: [ClashRule]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("#")
                        .frame(width: 50, alignment: .leading)
                    Text("Type")
                        .frame(width: 120, alignment: .leading)
                    Text("Payload")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Proxy")
                        .frame(width: 150, alignment: .leading)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
                
                ForEach(rules) { rule in
                    RuleRow(rule: rule)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }
}

struct RuleRow: View {
    let rule: ClashRule
    @State private var isHovered = false
    
    var typeColor: Color {
        switch rule.type {
        case "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD":
            return .blue
        case "IP-CIDR", "IP-CIDR6":
            return .green
        case "GEOIP", "GEOSITE":
            return .orange
        case "MATCH":
            return .purple
        case "PROCESS-NAME", "PROCESS-PATH":
            return .pink
        case "RULE-SET":
            return .cyan
        default:
            return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Text("\(rule.index)")
                .frame(width: 50, alignment: .leading)
                .foregroundStyle(.secondary)
            
            Text(rule.type)
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(typeColor)
            
            Text(rule.payload)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .help(rule.payload)
            
            Text(rule.proxy)
                .frame(width: 150, alignment: .leading)
                .foregroundStyle(.blue)
                .lineLimit(1)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    RulesView()
        .frame(width: 800, height: 600)
}
