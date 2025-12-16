import Foundation
import Combine
import Yams

@Observable
class ConfigurationManager {
    static let shared = ConfigurationManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var syncWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3
    private var isInitializing = true
    
    private let fileManager = FileManager.default
    
    private var configDirectory: URL {
        ClashCoreManager.shared.configDirectory
    }
    
    private var configPath: URL {
        ClashCoreManager.shared.configPath
    }
    
    private init() {
        setupObservers()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isInitializing = false
        }
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSync()
            }
            .store(in: &cancellables)
    }
    
    private func scheduleSync() {
        guard !isInitializing else { return }
        
        syncWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.syncConfiguration()
        }
        syncWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    func syncConfiguration() {
        if let selectedId = ProfileManager.shared.selectedProfileId,
           let profile = ProfileManager.shared.profiles.first(where: { $0.id == selectedId }) {
            applyProfileWithSettings(profile)
        } else {
            generateDefaultConfig()
        }
    }
    
    private func applyProfileWithSettings(_ profile: Profile) {
        let sourcePath = ProfileManager.shared.profilesDirectory.appendingPathComponent(profile.fileName)
        
        guard fileManager.fileExists(atPath: sourcePath.path) else {
            generateDefaultConfig()
            return
        }
        
        do {
            let profileContent = try String(contentsOf: sourcePath, encoding: .utf8)
            let mergedContent = mergeWithGeneralSettings(profileContent)
            
            try mergedContent.write(to: configPath, atomically: true, encoding: .utf8)
            
            reloadIfRunning()
        } catch {
            print("Failed to apply profile: \(error)")
        }
    }
    
    private func generateDefaultConfig() {
        let settings = AppSettings.shared
        var defaultConfig = """
mixed-port: \(settings.mixedPort)
port: \(settings.httpPort)
socks-port: \(settings.socksPort)
allow-lan: \(settings.allowLAN)
log-level: \(settings.logLevel.rawValue.lowercased())
external-controller: \(settings.externalController)
secret: \(settings.secret)
ipv6: \(settings.ipv6)
"""
        
        if settings.tunMode {
            defaultConfig += """

tun:
  enable: true
  stack: \(settings.tunStack.configValue)
  dns-hijack:
    - \(settings.tunDnsHijack)
  auto-route: \(settings.tunAutoRoute)
  auto-detect-interface: \(settings.tunAutoDetectInterface)
"""
        }
        
        try? fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try? defaultConfig.write(to: configPath, atomically: true, encoding: .utf8)
        
        reloadIfRunning()
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
        
        config["geo-auto-update"] = settings.autoUpdateGeoIP
        config["geo-update-interval"] = settings.geoUpdateInterval
        
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
    
    private func reloadIfRunning() {
        guard ClashCoreManager.shared.isRunning else { return }
        ClashCoreManager.shared.reloadConfigViaAPI()
    }
    
    func forceSync() {
        syncConfiguration()
    }
    
    func ensureConfigExists() {
        guard !fileManager.fileExists(atPath: configPath.path) else { return }
        syncConfiguration()
    }
}
