import Foundation
import Observation

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
class ClashCoreManager: CoreHealthMonitorDelegate {
    static let shared = ClashCoreManager()

    var currentCoreType: ClashCoreType = .meta
    var coreStatus: CoreStatus = .notInstalled
    var isRunning = false {
        didSet {
            if isRunning != oldValue {
                UserDefaults.standard.set(isRunning, forKey: "clashCoreWasRunning")
            }
        }
    }

    private var installedVersions: [ClashCoreType: String] = [:]
    private var coreProcess: Process?

    private let healthMonitor = CoreHealthMonitor()
    private let downloader = CoreDownloader.shared

    private var isStarting = false
    private let startLock = NSLock()

    var latestVersion: String = ""

    var isDownloading: Bool {
        downloader.isDownloading
    }

    var downloadProgress: Double {
        if case .downloading(let progress) = downloader.status {
            return progress
        }
        return 0
    }

    private let fileManager = FileManager.default

    var appSupportDirectory: URL {
        let paths = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        let appSupport = paths[0].appendingPathComponent(
            "Clash for macOS",
            isDirectory: true
        )
        try? fileManager.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        return appSupport
    }

    var coreDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent(
            "bin",
            isDirectory: true
        )
        try? fileManager.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    var corePath: URL {
        coreDirectory.appendingPathComponent(currentCoreType.executableName)
    }

    var configDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent(
            "config",
            isDirectory: true
        )
        try? fileManager.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    var configPath: URL {
        configDirectory.appendingPathComponent("config.yaml")
    }

    private var useServiceMode: Bool {
        HelperManager.shared.isHelperInstalled && AppSettings.shared.serviceMode
    }

    private init() {
        healthMonitor.delegate = self
        loadSettings()
        checkInstalledCore()
        checkRunningStatus()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let typeRaw = defaults.string(forKey: "clashCoreType"),
            let type = ClashCoreType(rawValue: typeRaw)
        {
            currentCoreType = type
        }

        for type in ClashCoreType.allCases {
            if let ver = defaults.string(
                forKey: "installedVersion_\(type.rawValue)"
            ) {
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

    func downloadCore() async {
        coreStatus = .downloading(progress: 0.1)

        let result = await downloader.download(
            coreType: currentCoreType,
            to: corePath
        )

        if result.success, let version = result.version {
            installedVersions[currentCoreType] = version
            latestVersion = version
            saveSettings()
            coreStatus = .installed(version: version)
        } else if case .failed(let error) = downloader.status {
            coreStatus = .error(error)
        }

        downloader.reset()
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

    func startCore() {
        startLock.lock()
        defer { startLock.unlock() }

        guard !isRunning && !isStarting else { return }
        guard fileManager.fileExists(atPath: corePath.path) else { return }

        isStarting = true
        healthMonitor.setManualStop(false)
        ConfigurationManager.shared.syncConfiguration()

        killOrphanClashProcesses()

        if useServiceMode {
            startCoreWithHelper()
        } else {
            startCoreDirectly()
        }
    }

    private func killOrphanClashProcesses() {
        for coreType in ClashCoreType.allCases {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            process.arguments = ["-9", "-f", coreType.executableName]
            try? process.run()
            process.waitUntilExit()
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func startCoreWithHelper() {
        HelperManager.shared.startClashCore(
            executablePath: corePath.path,
            configPath: configPath.path,
            workingDirectory: configDirectory.path
        ) { [weak self] success, pid, error in
            self?.isStarting = false
            if success {
                self?.isRunning = true
                self?.coreProcess = nil
                self?.healthMonitor.setProcess(nil)
                self?.healthMonitor.resetRestartAttempts()
                self?.healthMonitor.startMonitoring()
            } else {
                print(
                    "Failed to start core via helper: (error ?? \"Unknown error\")"
                )
                self?.isRunning = false
            }
        }
    }

    private func startCoreDirectly() {
        if let existingProcess = coreProcess, existingProcess.isRunning {
            isStarting = false
            isRunning = true
            return
        }

        coreProcess = nil

        let process = Process()
        process.executableURL = corePath
        process.arguments = ["-d", configDirectory.path]
        process.currentDirectoryURL = configDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                guard let self = self else { return }
                if self.coreProcess === terminatedProcess {
                    self.isRunning = false
                    self.coreProcess = nil
                }
            }
        }

        do {
            try process.run()
            coreProcess = process
            healthMonitor.setProcess(process)
            isRunning = true
            isStarting = false
            healthMonitor.resetRestartAttempts()
            healthMonitor.startMonitoring()
        } catch {
            print("Failed to start core: \(error)")
            isRunning = false
            isStarting = false
        }
    }

    func stopCore() {
        healthMonitor.setManualStop(true)
        healthMonitor.stopMonitoring()

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
                print(
                    "Failed to stop core via helper: \(error ?? "Unknown error")"
                )
            }
        }
    }

    private func stopCoreDirectly() {
        guard let process = coreProcess else { return }
        process.terminate()
        coreProcess = nil
        healthMonitor.setProcess(nil)
        isRunning = false
    }

    func restartCore() {
        healthMonitor.setManualStop(false)
        healthMonitor.stopMonitoring()

        if useServiceMode {
            HelperManager.shared.stopClashCore { [weak self] _, _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.isRunning = false
                    self?.startCore()
                }
            }
        } else {
            if let process = coreProcess {
                process.terminate()
                coreProcess = nil
            }
            isRunning = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.startCore()
            }
        }
    }

    func reloadConfigViaAPI() {
        guard isRunning else { return }
        Task {
            do {
                try await ClashAPI.shared.reloadConfigs(
                    force: true,
                    path: configPath.path
                )
            } catch {
                print("Failed to reload config via API: \(error)")
            }
        }
    }

    func updateConfigViaAPI(params: [String: Any]) {
        guard isRunning else { return }
        Task {
            do {
                try await ClashAPI.shared.updateConfigs(params: params)
            } catch {
                print("Failed to update config via API: \(error)")
            }
        }
    }

    func checkRunningStatus() {
        if useServiceMode {
            HelperManager.shared.isClashCoreRunning { [weak self] running, _ in
                Task { @MainActor in
                    self?.isRunning = running
                }
            }
        } else {
            isRunning = coreProcess?.isRunning ?? false
        }
    }

    func setAutoRestart(_ enabled: Bool) {
        healthMonitor.setAutoRestart(enabled)
    }

    func resetRestartAttempts() {
        healthMonitor.resetRestartAttempts()
    }

    func healthMonitor(
        _ monitor: CoreHealthMonitor,
        didDetectStateChange isRunning: Bool
    ) {
        self.isRunning = isRunning
    }

    func healthMonitorRequestsRestart(_ monitor: CoreHealthMonitor) {
        startCore()
    }
}
