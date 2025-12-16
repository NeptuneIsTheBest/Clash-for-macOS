import Foundation
import ServiceManagement
import Security

@Observable
class HelperManager {
    static let shared = HelperManager()
    
    private(set) var isHelperInstalled = false
    private(set) var helperVersion: String = ""
    private(set) var embeddedHelperVersion: String = ""
    private(set) var helperNeedsUpdate = false
    private var xpcConnection: NSXPCConnection?
    
    private let helperBundleID = "com.neptuneisthebest.Clash-for-macOS-Helper"
    private let helperPath = "/Library/PrivilegedHelperTools/Clash for macOS Helper"
    
    private init() {
        loadEmbeddedHelperVersion()
        checkHelperStatus()
    }
    
    func checkHelperStatus() {
        let service = SMAppService.daemon(plistName: "com.neptuneisthebest.Clash-for-macOS-Helper.plist")
        isHelperInstalled = (service.status == .enabled)
        
        if isHelperInstalled {
            getHelperVersion { [weak self] version in
                DispatchQueue.main.async {
                    self?.helperVersion = version
                    self?.checkIfUpdateNeeded()
                }
            }
        } else {
            helperVersion = ""
            helperNeedsUpdate = false
        }
    }
    
    private func loadEmbeddedHelperVersion() {
        let helperName = "com.neptuneisthebest.Clash-for-macOS-Helper"
        let bundleURL = Bundle.main.bundleURL
        
        let possibleURLs = [
            bundleURL.appendingPathComponent("Contents/Library/LaunchServices/\(helperName)"),
            bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons/\(helperName)")
        ]
        
        var helperURL: URL?
        for url in possibleURLs {
            if FileManager.default.fileExists(atPath: url.path) {
                helperURL = url
                break
            }
        }
        
        guard let url = helperURL else {
            embeddedHelperVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            return
        }
        
        var staticCode: SecStaticCode?
        if SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
           let code = staticCode {
            var info: CFDictionary?
            if SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
               let infoDict = info as? [String: Any],
               let plist = infoDict[kSecCodeInfoPList as String] as? [String: Any],
               let version = plist["CFBundleShortVersionString"] as? String {
                embeddedHelperVersion = version
                return
            }
        }
        
        embeddedHelperVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
    
    private func checkIfUpdateNeeded() {
        guard !helperVersion.isEmpty, !embeddedHelperVersion.isEmpty else {
            helperNeedsUpdate = false
            return
        }
        helperNeedsUpdate = compareVersions(helperVersion, embeddedHelperVersion) == .orderedAscending
    }
    
    private func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let components1 = v1.split(separator: ".").compactMap { Int($0) }
        let components2 = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(components1.count, components2.count)
        
        for i in 0..<maxCount {
            let num1 = i < components1.count ? components1[i] : 0
            let num2 = i < components2.count ? components2[i] : 0
            
            if num1 < num2 {
                return .orderedAscending
            } else if num1 > num2 {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
    
    func updateHelper(completion: @escaping (Bool, String?) -> Void) {
        let service = SMAppService.daemon(plistName: "com.neptuneisthebest.Clash-for-macOS-Helper.plist")
        
        do {
            try service.unregister()
        } catch {
        }
        
        xpcConnection?.invalidate()
        xpcConnection = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            do {
                try service.register()
                DispatchQueue.main.async {
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
        let interface = NSXPCInterface(with: HelperProtocol.self)
        let expectedClasses = NSSet(objects: NSArray.self, NSString.self) as! Set<AnyHashable>
        interface.setClasses(expectedClasses, for: #selector(HelperProtocol.runPrivilegedCommand(command:arguments:withReply:)), argumentIndex: 1, ofReply: false)
        connection.remoteObjectInterface = interface
        
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
