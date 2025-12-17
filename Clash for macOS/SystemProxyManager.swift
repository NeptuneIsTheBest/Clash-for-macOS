import Foundation
import Observation

@Observable
class SystemProxyManager {
    static let shared = SystemProxyManager()
    
    private(set) var isProxyEnabled = false
    private(set) var lastError: String?
    
    private let helperManager = HelperManager.shared
    private let settings = AppSettings.shared
    
    private init() {}
    
    func enableSystemProxy(completion: (@Sendable (Bool, String?) -> Void)? = nil) {
        let bypassDomains = settings.bypassSystemProxy ? settings.bypassDomains : ""
        
        if helperManager.isHelperInstalled {
            helperManager.setSystemProxy(
                httpPort: settings.mixedPort,
                socksPort: settings.socksPort,
                bypassDomains: bypassDomains
            ) { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.isProxyEnabled = true
                        self?.lastError = nil
                    } else {
                        self?.lastError = error
                    }
                    completion?(success, error)
                }
            }
        } else {
            setProxyViaNetworkSetup(enable: true, completion: completion)
        }
    }
    
    func disableSystemProxy(completion: (@Sendable (Bool, String?) -> Void)? = nil) {
        if helperManager.isHelperInstalled {
            helperManager.clearSystemProxy { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.isProxyEnabled = false
                        self?.lastError = nil
                    } else {
                        self?.lastError = error
                    }
                    completion?(success, error)
                }
            }
        } else {
            setProxyViaNetworkSetup(enable: false, completion: completion)
        }
    }
    
    func toggleSystemProxy(enabled: Bool, completion: (@Sendable (Bool, String?) -> Void)? = nil) {
        if enabled {
            enableSystemProxy(completion: completion)
        } else {
            disableSystemProxy(completion: completion)
        }
    }
    
    private func setProxyViaNetworkSetup(enable: Bool, completion: (@Sendable (Bool, String?) -> Void)?) {
        let mixedPort = settings.mixedPort
        let socksPort = settings.socksPort
        let bypassSystemProxy = settings.bypassSystemProxy
        let bypassDomains = settings.bypassDomains
        
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            
            let services = self.getActiveNetworkServicesSync()
            guard !services.isEmpty else {
                DispatchQueue.main.async {
                    self.lastError = "No active network services"
                    completion?(false, "No active network services")
                }
                return
            }
            
            let lastError: String? = nil
            
            for service in services {
                if enable {
                    self.runNetworkSetupSync(["-setwebproxy", service, "127.0.0.1", mixedPort])
                    self.runNetworkSetupSync(["-setsecurewebproxy", service, "127.0.0.1", mixedPort])
                    self.runNetworkSetupSync(["-setsocksfirewallproxy", service, "127.0.0.1", socksPort])
                    
                    if bypassSystemProxy {
                        let domains = bypassDomains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        self.runNetworkSetupSync(["-setproxybypassdomains", service] + domains)
                    }
                    
                    self.runNetworkSetupSync(["-setwebproxystate", service, "on"])
                    self.runNetworkSetupSync(["-setsecurewebproxystate", service, "on"])
                    self.runNetworkSetupSync(["-setsocksfirewallproxystate", service, "on"])
                } else {
                    self.runNetworkSetupSync(["-setwebproxystate", service, "off"])
                    self.runNetworkSetupSync(["-setsecurewebproxystate", service, "off"])
                    self.runNetworkSetupSync(["-setsocksfirewallproxystate", service, "off"])
                }
            }
            
            DispatchQueue.main.async {
                self.isProxyEnabled = enable
                self.lastError = lastError
                completion?(lastError == nil, lastError)
            }
        }
    }
    
    private nonisolated func getActiveNetworkServicesSync() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallnetworkservices"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            let lines = output.components(separatedBy: "\n")
            return lines.filter { !$0.isEmpty && !$0.hasPrefix("*") && !$0.hasPrefix("An asterisk") }
        } catch {
            return []
        }
    }
    
    @discardableResult
    private nonisolated func runNetworkSetupSync(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
