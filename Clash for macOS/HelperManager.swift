import Foundation
import ServiceManagement

@Observable
class HelperManager {
    static let shared = HelperManager()
    
    private(set) var isHelperInstalled = false
    private(set) var helperVersion: String = ""
    private var xpcConnection: NSXPCConnection?
    
    private let helperBundleID = "com.neptuneisthebest.Clash-for-macOS-Helper"
    private let helperPath = "/Library/PrivilegedHelperTools/Clash for macOS Helper"
    
    private init() {
        checkHelperStatus()
    }
    
    func checkHelperStatus() {
        let service = SMAppService.daemon(plistName: "com.neptuneisthebest.Clash-for-macOS-Helper.plist")
        isHelperInstalled = (service.status == .enabled)
        
        if isHelperInstalled {
            getHelperVersion { [weak self] version in
                DispatchQueue.main.async {
                    self?.helperVersion = version
                }
            }
        }
    }
    
    func installHelper(completion: @escaping (Bool, String?) -> Void) {
        let service = SMAppService.daemon(plistName: "com.neptuneisthebest.Clash-for-macOS-Helper.plist")
        
        do {
            try service.register()
            DispatchQueue.main.async { [weak self] in
                self?.checkHelperStatus()
            }
            completion(true, nil)
        } catch {
            let nsError = error as NSError
            if nsError.domain == "SMAppServiceErrorDomain" && nsError.code == 1 {
                completion(false, "User cancelled authorization")
            } else {
                completion(false, error.localizedDescription)
            }
        }
    }
    
    func uninstallHelper(completion: @escaping (Bool, String?) -> Void) {
        let service = SMAppService.daemon(plistName: "com.neptuneisthebest.Clash-for-macOS-Helper.plist")
        
        do {
            try service.unregister()
            DispatchQueue.main.async { [weak self] in
                self?.isHelperInstalled = false
                self?.helperVersion = ""
                self?.xpcConnection?.invalidate()
                self?.xpcConnection = nil
            }
            completion(true, nil)
        } catch {
            completion(false, error.localizedDescription)
        }
    }
    
    private func getConnection() -> NSXPCConnection {
        if let connection = xpcConnection {
            return connection
        }
        
        let connection = NSXPCConnection(machServiceName: kHelperToolMachServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.xpcConnection = nil
            }
        }
        
        connection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.xpcConnection?.invalidate()
                self?.xpcConnection = nil
            }
        }
        
        connection.resume()
        xpcConnection = connection
        return connection
    }
    
    private func getHelper() -> HelperProtocol? {
        let connection = getConnection()
        return connection.remoteObjectProxyWithErrorHandler { error in
            print("XPC Error: \(error.localizedDescription)")
        } as? HelperProtocol
    }
    
    func getHelperVersion(completion: @escaping (String) -> Void) {
        guard let helper = getHelper() else {
            completion("")
            return
        }
        helper.getVersion { version in
            completion(version)
        }
    }
    
    func setSystemProxy(host: String = "127.0.0.1", httpPort: String, socksPort: String, bypassDomains: String, completion: @escaping (Bool, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, "Helper not available")
            return
        }
        helper.setSystemProxy(host: host, httpPort: httpPort, socksPort: socksPort, bypassDomains: bypassDomains) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    func clearSystemProxy(completion: @escaping (Bool, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, "Helper not available")
            return
        }
        helper.clearSystemProxy { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    func startClashCore(executablePath: String, configPath: String, workingDirectory: String, completion: @escaping (Bool, Int32, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, 0, "Helper not available")
            return
        }
        helper.startClashCore(executablePath: executablePath, configPath: configPath, workingDirectory: workingDirectory) { success, pid, error in
            DispatchQueue.main.async {
                completion(success, pid, error)
            }
        }
    }
    
    func stopClashCore(completion: @escaping (Bool, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, "Helper not available")
            return
        }
        helper.stopClashCore { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    func isClashCoreRunning(completion: @escaping (Bool, Int32) -> Void) {
        guard let helper = getHelper() else {
            completion(false, 0)
            return
        }
        helper.isClashCoreRunning { running, pid in
            DispatchQueue.main.async {
                completion(running, pid)
            }
        }
    }
    
    func runCommand(command: String, arguments: [String], completion: @escaping (Bool, String?, String?) -> Void) {
        guard let helper = getHelper() else {
            completion(false, nil, "Helper not available")
            return
        }
        helper.runPrivilegedCommand(command: command, arguments: arguments) { success, output, error in
            DispatchQueue.main.async {
                completion(success, output, error)
            }
        }
    }
}
