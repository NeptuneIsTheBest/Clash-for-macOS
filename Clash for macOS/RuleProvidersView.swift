import SwiftUI

struct RuleProvidersView: View {
    @Bindable private var manager = RuleProviderManager.shared
    @State private var searchText = ""
    
    var filteredProviders: [ClashAPI.RuleProvider] {
        if searchText.isEmpty {
            return manager.providers
        } else {
            return manager.providers.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.behavior.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack {
                SettingsHeader(title: "Rule Providers", subtitle: "\(manager.providers.count) providers loaded") {
                    HStack(spacing: 10) {
                        
                        
                        Button(action: {
                            Task { await manager.updateAllProviders() }
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(manager.isLoading)
                        .help("Update All Providers")
                    }
                }
                
                SearchField(placeholder: "Search providers...", text: $searchText)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 15)
            
            if manager.isLoading && manager.providers.isEmpty {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading providers...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer()
            } else if let error = manager.errorMessage {
                Spacer()
                VStack(spacing: 15) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("Failed to load providers")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await manager.fetchProviders() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                Spacer()
            } else if manager.providers.isEmpty {
                Spacer()
                VStack(spacing: 15) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.gray)
                    Text("No Rule Providers")
                        .font(.title3)
                        .foregroundStyle(.gray)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProviders, id: \.name) { provider in
                            RuleProviderCard(provider: provider)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            }
        }
        .task {
            if manager.providers.isEmpty {
                await manager.fetchProviders()
            }
        }
        .onChange(of: ClashCoreManager.shared.isRunning) { _, isRunning in
            if isRunning {
                Task { await manager.fetchProviders() }
            }
        }
    }
}

@Observable
class RuleProviderManager {
    static let shared = RuleProviderManager()
    
    var providers: [ClashAPI.RuleProvider] = []
    var isLoading = false
    var errorMessage: String?
    var updatingProviders: Set<String> = []
    
    private init() {}
    
    func fetchProviders() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let providersDict = try await ClashAPI.shared.getRuleProviders()
            providers = providersDict.values.sorted { $0.name < $1.name }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    func updateProvider(_ name: String) async {
        updatingProviders.insert(name)
        do {
            try await ClashAPI.shared.updateRuleProvider(name: name)

            try? await Task.sleep(for: .seconds(0.5))
            await fetchProviders()
        } catch {
            print("Failed to update provider \(name): \(error)")
        }
        updatingProviders.remove(name)
    }
    
    func updateAllProviders() async {
        isLoading = true
        for provider in providers {
            await updateProvider(provider.name)
        }
        isLoading = false
    }
}

struct RuleProviderCard: View {
    let provider: ClashAPI.RuleProvider
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(provider.name)
                            .font(.headline)
                        
                        Text(provider.behavior)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                        
                        Text(provider.type)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .foregroundStyle(.secondary)
                            .cornerRadius(4)
                    }
                    
                    Text("Updated: \(formatDate(provider.updatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(provider.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Rules")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 10)
                
                Button(action: {
                    Task {
                        await RuleProviderManager.shared.updateProvider(provider.name)
                    }
                }) {
                    if RuleProviderManager.shared.updatingProviders.contains(provider.name) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())
                .help("Update Provider")
            }
            
            HStack {
                Text(provider.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(15)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(isHovered ? 0.1 : 0.05), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "Never" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date.formatted(date: .abbreviated, time: .standard)
        }
        return dateString
    }
}

#Preview {
    RuleProvidersView()
}
