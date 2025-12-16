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
    
    enum ProfileType: String, Codable {
        case remote
        case local
    }
    
    init(id: UUID = UUID(), name: String, type: ProfileType, url: String? = nil, lastUpdated: Date = Date(), fileName: String = "") {
        self.id = id
        self.name = name
        self.type = type
        self.url = url
        self.lastUpdated = lastUpdated
        self.fileName = fileName
    }
}

enum ProfileDownloadStatus {
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
    
    @discardableResult
    func importProfile(from url: URL) async -> Bool {
        guard url.startAccessingSecurityScopedResource() else {
            downloadStatus = .failed("Permission denied")
            return false
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let profileName = url.deletingPathExtension().lastPathComponent
            let fileName = "\(UUID().uuidString).yaml"
            let filePath = profilesDirectory.appendingPathComponent(fileName)
            
            try data.write(to: filePath)
            
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
            
            let profileName = extractProfileName(from: httpResponse, url: url, data: data)
            let fileName = "\(UUID().uuidString).yaml"
            let filePath = profilesDirectory.appendingPathComponent(fileName)
            
            try data.write(to: filePath)
            
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
    func updateProfile(_ profile: Profile) async -> Bool {
        guard profile.type == .remote, let urlString = profile.url else { return false }
        guard let url = URL(string: urlString) else { return false }
        
        downloadStatus = .downloading
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("ClashForMacOS/1.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                downloadStatus = .failed("Update failed")
                return false
            }
            
            let filePath = profilesDirectory.appendingPathComponent(profile.fileName)
            try data.write(to: filePath)
            
            await MainActor.run {
                if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                    profiles[index].lastUpdated = Date()
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
        applyProfile(profile)
    }
    
    func applyProfile(_ profile: Profile) {
        let sourcePath = profilesDirectory.appendingPathComponent(profile.fileName)
        let destPath = ClashCoreManager.shared.configPath
        
        guard fileManager.fileExists(atPath: sourcePath.path) else { return }
        
        do {
            let profileContent = try String(contentsOf: sourcePath, encoding: .utf8)
            let mergedContent = mergeWithGeneralSettings(profileContent)
            
            try mergedContent.write(to: destPath, atomically: true, encoding: .utf8)
            
            if ClashCoreManager.shared.isRunning {
                ClashCoreManager.shared.restartCore()
            }
        } catch {
            print("Failed to apply profile: \(error)")
        }
    }
    
    private func mergeWithGeneralSettings(_ profileContent: String) -> String {
        let settings = AppSettings.shared
        
        guard var config = try? Yams.load(yaml: profileContent) as? [String: Any] else {
            return profileContent
        }
        
        config["mixed-port"] = Int(settings.mixedPort) ?? 7890
        config["port"] = Int(settings.httpPort) ?? 7890
        config["socks-port"] = Int(settings.socksPort) ?? 7891
        config["allow-lan"] = settings.allowLAN
        config["log-level"] = settings.logLevel.rawValue.lowercased()
        config["external-controller"] = settings.externalController
        config["secret"] = settings.secret
        config["ipv6"] = settings.ipv6
        
        if settings.tunMode {
            config["tun"] = [
                "enable": true,
                "stack": settings.tunStack.configValue,
                "dns-hijack": [settings.tunDnsHijack],
                "auto-route": settings.tunAutoRoute,
                "auto-detect-interface": settings.tunAutoDetectInterface
            ]
        } else {
            config.removeValue(forKey: "tun")
        }
        
        guard let result = try? Yams.dump(object: config, allowUnicode: true) else {
            return profileContent
        }
        
        return result
    }
    
    private func extractProfileName(from response: HTTPURLResponse, url: URL, data: Data) -> String {
        if let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           let match = disposition.range(of: "filename=\"([^\"]+)\"", options: .regularExpression) {
            let filename = String(disposition[match]).replacingOccurrences(of: "filename=\"", with: "").replacingOccurrences(of: "\"", with: "")
            return filename.replacingOccurrences(of: ".yaml", with: "").replacingOccurrences(of: ".yml", with: "")
        }
        
        if let content = String(data: data.prefix(500), encoding: .utf8),
           let nameMatch = content.range(of: "#\\s*(.+)", options: .regularExpression) {
            let comment = String(content[nameMatch]).dropFirst().trimmingCharacters(in: .whitespaces)
            if !comment.isEmpty && comment.count < 50 {
                return String(comment)
            }
        }
        
        let pathName = url.deletingPathExtension().lastPathComponent
        if !pathName.isEmpty && pathName != "config" {
            return pathName
        }
        
        return url.host ?? "Remote Profile"
    }
}

struct ProfilesConfig: Codable {
    var profiles: [Profile]
    var selectedProfileId: UUID?
}
