import Foundation
import Observation

struct GitHubRelease: Codable {
    let tag_name: String
    let assets: [GitHubAsset]
    
    struct GitHubAsset: Codable {
        let name: String
        let browser_download_url: String
    }
}

enum ClashCoreType: String, CaseIterable, Codable {
    case meta = "Meta"
    case rust = "Rust"
    
    var displayName: String { rawValue }
    
    var repoPath: String {
        switch self {
        case .meta: return "MetaCubeX/mihomo"
        case .rust: return "Watfaq/clash-rs"
        }
    }
    
    var executableName: String {
        switch self {
        case .meta: return "clash-meta"
        case .rust: return "clash-rust"
        }
    }
}

enum CoreStatus {
    case notInstalled
    case installed(version: String)
    case downloading(progress: Double)
    case error(String)
}

@Observable
class ClashCoreManager {
    static let shared = ClashCoreManager()
    
    var currentCoreType: ClashCoreType = .meta
    var coreStatus: CoreStatus = .notInstalled
    var isRunning = false
    
    private var installedVersions: [ClashCoreType: String] = [:]
    private var coreProcess: Process?
    
    var latestVersion: String = ""
    var isDownloading = false
    var downloadProgress: Double = 0
    
    private let fileManager = FileManager.default
    
    private var systemArch: String {
        #if arch(x86_64)
        return "x86_64"
        #else
        return "arm64"
        #endif
    }
    
    var appSupportDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("Clash for macOS", isDirectory: true)
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }
    
    var coreDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("bin", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    var corePath: URL {
        coreDirectory.appendingPathComponent(currentCoreType.executableName)
    }
    
    private init() {
        loadSettings()
        checkInstalledCore()
        checkRunningStatus()
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let typeRaw = defaults.string(forKey: "clashCoreType"),
           let type = ClashCoreType(rawValue: typeRaw) {
            currentCoreType = type
        }
        
        for type in ClashCoreType.allCases {
            if let ver = defaults.string(forKey: "installedVersion_\(type.rawValue)") {
                installedVersions[type] = ver
            }
        }
    }
    
    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(currentCoreType.rawValue, forKey: "clashCoreType")
        
        for (type, version) in installedVersions {
            defaults.set(version, forKey: "installedVersion_\(type.rawValue)")
        }
    }
    
    func checkInstalledCore() {
        if fileManager.fileExists(atPath: corePath.path) {
            let version = installedVersions[currentCoreType] ?? "Unknown"
            coreStatus = .installed(version: version)
        } else {
            coreStatus = .notInstalled
        }
    }
    
    func selectCoreType(_ type: ClashCoreType) {
        currentCoreType = type
        saveSettings()
        checkInstalledCore()
    }
    
    private func getMatchRules() -> (keywords: [String], suffix: String?) {
        let arch = systemArch
        
        switch currentCoreType {
        case .meta:
            let metaArch = (arch == "x86_64") ? "amd64" : "arm64"
            return (["mihomo", "darwin", metaArch], ".gz")
            
        case .rust:
            let rustArch = (arch == "x86_64") ? "x86_64" : "aarch64"
            return (["clash", rustArch, "apple", "darwin"], nil)
        }
    }
    
    private func fetchLatestReleaseInfo() async throws -> (version: String, downloadURL: URL, fileName: String) {
        let urlString = "https://api.github.com/repos/\(currentCoreType.repoPath)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("ClashForMacOS/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        let (keywords, requiredSuffix) = getMatchRules()
        
        guard let asset = release.assets.first(where: { asset in
            let name = asset.name.lowercased()
            
            let matchKeywords = keywords.allSatisfy { name.contains($0) }
            
            let matchSuffix: Bool
            if let suffix = requiredSuffix {
                matchSuffix = name.hasSuffix(suffix)
            } else {
                matchSuffix = !name.hasSuffix(".gz") && !name.hasSuffix(".zip") && !name.hasSuffix(".sha256")
            }
            
            return matchKeywords && matchSuffix
        }) else {
            throw NSError(domain: "ClashCore", code: 404, userInfo: [NSLocalizedDescriptionKey: "No compatible asset found for \(systemArch)"])
        }
        
        guard let downloadURL = URL(string: asset.browser_download_url) else {
            throw URLError(.badURL)
        }
        
        return (release.tag_name, downloadURL, asset.name)
    }
    
    func downloadCore() async {
        guard !isDownloading else { return }
        
        isDownloading = true
        downloadProgress = 0
        coreStatus = .downloading(progress: 0.1)
        
        do {
            let (version, validDownloadURL, fileName) = try await fetchLatestReleaseInfo()
            
            let (tempURL, _) = try await URLSession.shared.download(from: validDownloadURL, delegate: nil)
            
            downloadProgress = 0.5
            coreStatus = .downloading(progress: 0.5)
            
            try fileManager.createDirectory(at: coreDirectory, withIntermediateDirectories: true)
            
            if fileManager.fileExists(atPath: corePath.path) {
                try fileManager.removeItem(at: corePath)
            }
            
            if fileName.hasSuffix(".gz") {
                let tempGzURL = tempURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".gz")
                try fileManager.moveItem(at: tempURL, to: tempGzURL)
                let decompressedData = try decompressGzip(at: tempGzURL)
                try? fileManager.removeItem(at: tempGzURL)
                try decompressedData.write(to: corePath)
            } else {
                try fileManager.moveItem(at: tempURL, to: corePath)
            }
            
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: corePath.path)
            
            downloadProgress = 1.0
            installedVersions[currentCoreType] = version
            latestVersion = version
            saveSettings()
            
            coreStatus = .installed(version: version)
            isDownloading = false
            
        } catch {
            print("Download error: \(error)")
            coreStatus = .error(error.localizedDescription)
            isDownloading = false
        }
    }
    
    private func decompressGzip(at url: URL) throws -> Data {
        let outputURL = url.deletingPathExtension()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-k", "-f", url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ClashCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decompress gzip file"])
        }
        let decompressedData = try Data(contentsOf: outputURL)
        try? fileManager.removeItem(at: outputURL)
        return decompressedData
    }
    
    func deleteCore() throws {
        stopCore()
        if fileManager.fileExists(atPath: corePath.path) {
            try fileManager.removeItem(at: corePath)
        }
        installedVersions.removeValue(forKey: currentCoreType)
        saveSettings()
        coreStatus = .notInstalled
    }
    
    var configDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("config", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    var configPath: URL {
        configDirectory.appendingPathComponent("config.yaml")
    }
    
    private var useServiceMode: Bool {
        HelperManager.shared.isHelperInstalled && AppSettings.shared.serviceMode
    }
    
    func startCore() {
        guard !isRunning else { return }
        guard fileManager.fileExists(atPath: corePath.path) else { return }
        
        ensureDefaultConfig()
        
        if useServiceMode {
            startCoreWithHelper()
        } else {
            startCoreDirectly()
        }
    }
    
    private func startCoreWithHelper() {
        HelperManager.shared.startClashCore(
            executablePath: corePath.path,
            configPath: configPath.path,
            workingDirectory: configDirectory.path
        ) { [weak self] success, pid, error in
            if success {
                self?.isRunning = true
                self?.coreProcess = nil
            } else {
                print("Failed to start core via helper: \(error ?? "Unknown error")")
                self?.isRunning = false
            }
        }
    }
    
    private func startCoreDirectly() {
        let process = Process()
        process.executableURL = corePath
        process.arguments = ["-d", configDirectory.path]
        process.currentDirectoryURL = configDirectory
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.coreProcess = nil
            }
        }
        
        do {
            try process.run()
            coreProcess = process
            isRunning = true
        } catch {
            print("Failed to start core: \(error)")
            isRunning = false
        }
    }
    
    func stopCore() {
        guard isRunning else { return }
        
        if useServiceMode {
            stopCoreWithHelper()
        } else {
            stopCoreDirectly()
        }
    }
    
    private func stopCoreWithHelper() {
        HelperManager.shared.stopClashCore { [weak self] success, error in
            if success {
                self?.isRunning = false
            } else {
                print("Failed to stop core via helper: \(error ?? "Unknown error")")
            }
        }
    }
    
    private func stopCoreDirectly() {
        guard let process = coreProcess else { return }
        process.terminate()
        coreProcess = nil
        isRunning = false
    }
    
    func restartCore() {
        stopCore()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startCore()
        }
    }
    
    func checkRunningStatus() {
        if HelperManager.shared.isHelperInstalled {
            HelperManager.shared.isClashCoreRunning { [weak self] running, _ in
                self?.isRunning = running
            }
        }
    }
    
    private func ensureDefaultConfig() {
        guard !fileManager.fileExists(atPath: configPath.path) else { return }
        
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
        
        try? defaultConfig.write(to: configPath, atomically: true, encoding: .utf8)
    }
}
