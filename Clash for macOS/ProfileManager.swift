import Foundation
import Observation
import Yams

struct Profile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: ProfileType
    var url: String?
    var lastUpdated: Date
    var fileName: String
    var notes: String?
    var userAgent: String
    var updateInterval: Int
    var useSystemProxy: Bool
    var useClashProxy: Bool
    var lastAutoUpdate: Date?
    
    enum ProfileType: String, Codable {
        case remote
        case local
    }
    
    init(id: UUID = UUID(), name: String, type: ProfileType, url: String? = nil, lastUpdated: Date = Date(), fileName: String = "", notes: String? = nil, userAgent: String = "ClashForMacOS/1.0", updateInterval: Int = 1440, useSystemProxy: Bool = false, useClashProxy: Bool = false, lastAutoUpdate: Date? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.url = url
        self.lastUpdated = lastUpdated
        self.fileName = fileName
        self.notes = notes
        self.userAgent = userAgent
        self.updateInterval = updateInterval
        self.useSystemProxy = useSystemProxy
        self.useClashProxy = useClashProxy
        self.lastAutoUpdate = lastAutoUpdate
    }
}

enum ProfileDownloadStatus: Equatable {
    case idle
    case downloading
    case success
    case failed(String)
}

@Observable
class ProfileManager {
    static let shared = ProfileManager()
    
    var profiles: [Profile] = []
    var selectedProfileId: UUID?
    var downloadStatus: ProfileDownloadStatus = .idle
    
    private let fileManager = FileManager.default
    private var autoUpdateTimer: Timer?
    
    var profilesDirectory: URL {
        let dir = ClashCoreManager.shared.appSupportDirectory.appendingPathComponent("profiles", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var profilesConfigPath: URL {
        ClashCoreManager.shared.appSupportDirectory.appendingPathComponent("profiles.json")
    }
    
    private init() {
        loadProfiles()
        startAutoUpdateTimer()
    }
    
    func startAutoUpdateTimer() {
        autoUpdateTimer?.invalidate()
        autoUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAndUpdateProfiles()
            }
        }
    }
    
    func stopAutoUpdateTimer() {
        autoUpdateTimer?.invalidate()
        autoUpdateTimer = nil
    }
    
    func checkAndUpdateProfiles() async {
        let now = Date()
        for profile in profiles where profile.type == .remote && profile.updateInterval > 0 {
            let lastUpdate = profile.lastAutoUpdate ?? profile.lastUpdated
            let intervalSeconds = TimeInterval(profile.updateInterval * 60)
            if now.timeIntervalSince(lastUpdate) >= intervalSeconds {
                await updateProfile(profile, isAutoUpdate: true)
            }
        }
    }
    
    private func createURLSession(for profile: Profile) -> URLSession {
        let config = URLSessionConfiguration.default
        
        if profile.useClashProxy {
            let settings = AppSettings.shared
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: true,
                kCFNetworkProxiesHTTPProxy: "127.0.0.1",
                kCFNetworkProxiesHTTPPort: Int(settings.httpPort) ?? 7890,
                kCFProxyTypeHTTPS: true,
                "HTTPSProxy": "127.0.0.1",
                "HTTPSPort": Int(settings.httpPort) ?? 7890
            ]
        } else if profile.useSystemProxy {
        }
        
        return URLSession(configuration: config)
    }
    
    func loadProfiles() {
        guard fileManager.fileExists(atPath: profilesConfigPath.path) else { return }
        
        do {
            let data = try Data(contentsOf: profilesConfigPath)
            let decoded = try JSONDecoder().decode(ProfilesConfig.self, from: data)
            profiles = decoded.profiles
            selectedProfileId = decoded.selectedProfileId
        } catch {
            print("Failed to load profiles: \(error)")
        }
    }
    
    func saveProfiles() {
        let config = ProfilesConfig(profiles: profiles, selectedProfileId: selectedProfileId)
        
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: profilesConfigPath)
        } catch {
            print("Failed to save profiles: \(error)")
        }
    }
    
    func validateAndNormalizeYAML(_ content: String) throws -> String {
        guard let parsed = try Yams.load(yaml: content) else {
            throw YAMLValidationError.emptyContent
        }
        
        let normalized = try Yams.dump(object: parsed, allowUnicode: true)
        return normalized
    }
    
    func validateYAML(_ content: String) -> String? {
        do {
            _ = try validateAndNormalizeYAML(content)
            return nil
        } catch let error as Yams.YamlError {
            return error.localizedDescription
        } catch {
            return error.localizedDescription
        }
    }
    
    @discardableResult
    func importProfile(from url: URL) async -> Bool {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) else {
                await MainActor.run {
                    downloadStatus = .failed("Invalid file encoding")
                }
                return false
            }
            
            let normalizedContent: String
            do {
                normalizedContent = try validateAndNormalizeYAML(content)
            } catch {
                await MainActor.run {
                    downloadStatus = .failed("Invalid YAML: \(error.localizedDescription)")
                }
                return false
            }
            
            let profileName = url.deletingPathExtension().lastPathComponent
            let fileName = "\(UUID().uuidString).yaml"
            let filePath = profilesDirectory.appendingPathComponent(fileName)
            
            try normalizedContent.write(to: filePath, atomically: true, encoding: .utf8)
            
            let profile = Profile(
                name: profileName,
                type: .local,
                url: nil,
                lastUpdated: Date(),
                fileName: fileName
            )
            
            await MainActor.run {
                profiles.append(profile)
                if selectedProfileId == nil {
                    selectedProfileId = profile.id
                }
                saveProfiles()
                downloadStatus = .success
            }
            
            return true
            
        } catch {
            await MainActor.run {
                downloadStatus = .failed(error.localizedDescription)
            }
            return false
        }
    }

    @discardableResult
    func downloadProfile(from urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else {
            downloadStatus = .failed("Invalid URL")
            return false
        }
        
        downloadStatus = .downloading
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("ClashForMacOS/1.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                downloadStatus = .failed("Download failed")
                return false
            }
            
            guard let content = String(data: data, encoding: .utf8) else {
                await MainActor.run {
                    downloadStatus = .failed("Invalid file encoding")
                }
                return false
            }
            
            let normalizedContent: String
            do {
                normalizedContent = try validateAndNormalizeYAML(content)
            } catch {
                await MainActor.run {
                    downloadStatus = .failed("Invalid YAML: \(error.localizedDescription)")
                }
                return false
            }
            
            let profileName = extractProfileName(from: httpResponse, url: url, data: data)
            let fileName = "\(UUID().uuidString).yaml"
            let filePath = profilesDirectory.appendingPathComponent(fileName)
            
            try normalizedContent.write(to: filePath, atomically: true, encoding: .utf8)
            
            let profile = Profile(
                name: profileName,
                type: .remote,
                url: urlString,
                lastUpdated: Date(),
                fileName: fileName
            )
            
            await MainActor.run {
                profiles.append(profile)
                if selectedProfileId == nil {
                    selectedProfileId = profile.id
                }
                saveProfiles()
                downloadStatus = .success
            }
            
            return true
            
        } catch {
            await MainActor.run {
                downloadStatus = .failed(error.localizedDescription)
            }
            return false
        }
    }
    
    @discardableResult
    func updateProfile(_ profile: Profile, isAutoUpdate: Bool = false) async -> Bool {
        guard profile.type == .remote, let urlString = profile.url else { return false }
        guard let url = URL(string: urlString) else { return false }
        
        if !isAutoUpdate {
            downloadStatus = .downloading
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
            
            let session = createURLSession(for: profile)
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                if !isAutoUpdate {
                    downloadStatus = .failed("Update failed")
                }
                return false
            }
            
            guard let content = String(data: data, encoding: .utf8) else {
                if !isAutoUpdate {
                    await MainActor.run {
                        downloadStatus = .failed("Invalid file encoding")
                    }
                }
                return false
            }
            
            let normalizedContent: String
            do {
                normalizedContent = try validateAndNormalizeYAML(content)
            } catch {
                if !isAutoUpdate {
                    await MainActor.run {
                        downloadStatus = .failed("Invalid YAML: \(error.localizedDescription)")
                    }
                }
                return false
            }
            
            let filePath = profilesDirectory.appendingPathComponent(profile.fileName)
            try normalizedContent.write(to: filePath, atomically: true, encoding: .utf8)
            
            await MainActor.run {
                if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                    profiles[index].lastUpdated = Date()
                    if isAutoUpdate {
                        profiles[index].lastAutoUpdate = Date()
                    }
                }
                saveProfiles()
                if !isAutoUpdate {
                    downloadStatus = .success
                }
            }
            
            return true
            
        } catch {
            await MainActor.run {
                if !isAutoUpdate {
                    downloadStatus = .failed(error.localizedDescription)
                }
            }
            return false
        }
    }
    
    func updateAllProfiles() async {
        for profile in profiles where profile.type == .remote {
            _ = await updateProfile(profile)
        }
    }
    
    func deleteProfile(_ profile: Profile) {
        let filePath = profilesDirectory.appendingPathComponent(profile.fileName)
        try? fileManager.removeItem(at: filePath)
        
        profiles.removeAll { $0.id == profile.id }
        
        if selectedProfileId == profile.id {
            selectedProfileId = profiles.first?.id
        }
        
        saveProfiles()
    }
    
    func selectProfile(_ profile: Profile) {
        selectedProfileId = profile.id
        saveProfiles()
        ConfigurationManager.shared.syncConfiguration()
    }
    
    func applyProfile(_ profile: Profile) {
        ConfigurationManager.shared.syncConfiguration()
    }
    
    func getProfileContent(_ profile: Profile) -> String {
        let filePath = profilesDirectory.appendingPathComponent(profile.fileName)
        return (try? String(contentsOf: filePath, encoding: .utf8)) ?? ""
    }
    
    func saveProfileContent(_ profile: Profile, content: String) {
        let filePath = profilesDirectory.appendingPathComponent(profile.fileName)
        try? content.write(to: filePath, atomically: true, encoding: .utf8)
        
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].lastUpdated = Date()
            saveProfiles()
        }
        
        if selectedProfileId == profile.id {
            ConfigurationManager.shared.syncConfiguration()
        }
    }
    
    func updateProfileMetadata(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
        }
    }
    
    private func extractProfileName(from response: HTTPURLResponse, url: URL, data: Data) -> String {
        return url.host ?? "Remote Profile"
    }
}

enum YAMLValidationError: Error, LocalizedError {
    case emptyContent
    
    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "YAML content is empty"
        }
    }
}

struct ProfilesConfig: Codable {
    var profiles: [Profile]
    var selectedProfileId: UUID?
}
