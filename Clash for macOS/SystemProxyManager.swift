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
    
    func enableSystemProxy(completion: ((Bool, String?) -> Void)? = nil) {
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
    
    func disableSystemProxy(completion: ((Bool, String?) -> Void)? = nil) {
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
    
    func toggleSystemProxy(enabled: Bool, completion: ((Bool, String?) -> Void)? = nil) {
        if enabled {
            enableSystemProxy(completion: completion)
        } else {
            disableSystemProxy(completion: completion)
        }
    }
    
    private func setProxyViaNetworkSetup(enable: Bool, completion: ((Bool, String?) -> Void)?) {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            
            let services = self.getActiveNetworkServices()
            guard !services.isEmpty else {
                DispatchQueue.main.async {
                    self.lastError = "No active network services"
                    completion?(false, "No active network services")
                }
                return
            }
            
            let lastError: String?
            
            for service in services {
                if enable {
                    self.runNetworkSetup(["-setwebproxy", service, "127.0.0.1", self.settings.mixedPort])
                    self.runNetworkSetup(["-setsecurewebproxy", service, "127.0.0.1", self.settings.mixedPort])
                    self.runNetworkSetup(["-setsocksfirewallproxy", service, "127.0.0.1", self.settings.socksPort])
                    
                    if self.settings.bypassSystemProxy {
                        let domains = self.settings.bypassDomains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        self.runNetworkSetup(["-setproxybypassdomains", service] + domains)
                    }
                    
                    self.runNetworkSetup(["-setwebproxystate", service, "on"])
                    self.runNetworkSetup(["-setsecurewebproxystate", service, "on"])
                    self.runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
                } else {
                    self.runNetworkSetup(["-setwebproxystate", service, "off"])
                    self.runNetworkSetup(["-setsecurewebproxystate", service, "off"])
                    self.runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
                }
            }
            
            DispatchQueue.main.async {
                self.isProxyEnabled = enable
                self.lastError = lastError
                completion?(lastError == nil, lastError)
            }
        }
    }
    
    private func getActiveNetworkServices() -> [String] {
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
    private func runNetworkSetup(_ arguments: [String]) -> Bool {
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
