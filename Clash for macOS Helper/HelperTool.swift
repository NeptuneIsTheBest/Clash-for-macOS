import Foundation
import Security

class HelperTool: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private var clashProcess: Process?
    private var clashProcessPID: Int32 = 0
    private let processLock = NSLock()
    
    private let allowedCommands: Set<String> = [
        "/usr/sbin/networksetup",
        "/sbin/route",
        "/usr/bin/killall",
        "/bin/launchctl"
    ]
    
    func run() {
        setupSignalHandlers()
        
        let listener = NSXPCListener(machServiceName: kHelperToolMachServiceName)
        listener.delegate = self
        listener.resume()
        RunLoop.current.run()
    }
    
    private func setupSignalHandlers() {
        let signalCallback: @convention(c) (Int32) -> Void = { signal in
            HelperTool.handleSignal(signal)
        }
        
        signal(SIGTERM, signalCallback)
        signal(SIGINT, signalCallback)
    }
    
    private static func handleSignal(_ sig: Int32) {
        exit(0)
    }
    
    deinit {
        cleanupClashProcess()
    }
    
    private func cleanupClashProcess() {
        processLock.lock()
        defer { processLock.unlock() }
        
        if let process = clashProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        clashProcess = nil
        clashProcessPID = 0
    }
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard isValidClient(connection: newConnection) else {
            return false
        }
        
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        
        newConnection.invalidationHandler = { [weak self] in
            self?.handleConnectionInvalidation()
        }
        
        newConnection.resume()
        return true
    }
    
    private func isValidClient(connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        guard pid > 0 else { return false }
        
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code)
        
        guard status == errSecSuccess, let secCode = code else {
            return false
        }
        
        let requirement = "identifier \"com.neptuneisthebest.Clash-for-macOS\""
        var secRequirement: SecRequirement?
        
        guard SecRequirementCreateWithString(requirement as CFString, [], &secRequirement) == errSecSuccess,
              let req = secRequirement else {
            return false
        }
        
        return SecCodeCheckValidity(secCode, [], req) == errSecSuccess
    }
    
    private func handleConnectionInvalidation() {
    }
    
    func getVersion(withReply reply: @escaping (String) -> Void) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        reply(version)
    }
    
    func setSystemProxy(host: String, httpPort: String, socksPort: String, bypassDomains: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let networkServices = getActiveNetworkServices()
        
        guard !networkServices.isEmpty else {
            reply(false, "No active network services found")
            return
        }
        
        var lastError: String?
        
        for service in networkServices {
            if !httpPort.isEmpty {
                let httpResult = runNetworkSetup(["-setwebproxy", service, host, httpPort])
                if !httpResult.success { lastError = httpResult.error }
                
                let httpsResult = runNetworkSetup(["-setsecurewebproxy", service, host, httpPort])
                if !httpsResult.success { lastError = httpsResult.error }
            }
            
            if !socksPort.isEmpty {
                let socksResult = runNetworkSetup(["-setsocksfirewallproxy", service, host, socksPort])
                if !socksResult.success { lastError = socksResult.error }
            }
            
            if !bypassDomains.isEmpty {
                let domains = bypassDomains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let bypassResult = runNetworkSetup(["-setproxybypassdomains", service] + domains)
                if !bypassResult.success { lastError = bypassResult.error }
            }
            
            if !httpPort.isEmpty {
                _ = runNetworkSetup(["-setwebproxystate", service, "on"])
                _ = runNetworkSetup(["-setsecurewebproxystate", service, "on"])
            }
            
            if !socksPort.isEmpty {
                _ = runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
            }
        }
        
        reply(lastError == nil, lastError)
    }
    
    func clearSystemProxy(withReply reply: @escaping (Bool, String?) -> Void) {
        let networkServices = getActiveNetworkServices()
        
        guard !networkServices.isEmpty else {
            reply(true, nil)
            return
        }
        
        var lastError: String?
        
        for service in networkServices {
            let httpOff = runNetworkSetup(["-setwebproxystate", service, "off"])
            if !httpOff.success { lastError = httpOff.error }
            
            let httpsOff = runNetworkSetup(["-setsecurewebproxystate", service, "off"])
            if !httpsOff.success { lastError = httpsOff.error }
            
            let socksOff = runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
            if !socksOff.success { lastError = socksOff.error }
        }
        
        reply(lastError == nil, lastError)
    }
    
    func startClashCore(executablePath: String, configPath: String, workingDirectory: String, withReply reply: @escaping (Bool, Int32, String?) -> Void) {
        processLock.lock()
        
        if let existingProcess = clashProcess, existingProcess.isRunning {
            existingProcess.terminate()
            existingProcess.waitUntilExit()
        }
        clashProcess = nil
        clashProcessPID = 0
        
        processLock.unlock()
        
        guard FileManager.default.fileExists(atPath: executablePath) else {
            reply(false, 0, "Executable not found: \(executablePath)")
            return
        }
        
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            reply(false, 0, "File is not executable: \(executablePath)")
            return
        }
        
        guard FileManager.default.fileExists(atPath: configPath) else {
            reply(false, 0, "Config file not found: \(configPath)")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-d", workingDirectory, "-f", configPath]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        process.terminationHandler = { [weak self] terminatedProcess in
            self?.processLock.lock()
            if self?.clashProcess === terminatedProcess {
                self?.clashProcess = nil
                self?.clashProcessPID = 0
            }
            self?.processLock.unlock()
        }
        
        do {
            try process.run()
            
            processLock.lock()
            clashProcess = process
            clashProcessPID = process.processIdentifier
            processLock.unlock()
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.processLock.lock()
                let isRunning = process.isRunning
                self?.processLock.unlock()
                
                if isRunning {
                    reply(true, process.processIdentifier, nil)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalError = errorString?.isEmpty == false ? errorString : "Process exited unexpectedly"
                    
                    self?.processLock.lock()
                    self?.clashProcess = nil
                    self?.clashProcessPID = 0
                    self?.processLock.unlock()
                    
                    reply(false, 0, finalError)
                }
            }
        } catch {
            reply(false, 0, error.localizedDescription)
        }
    }
    
    func stopClashCore(withReply reply: @escaping (Bool, String?) -> Void) {
        processLock.lock()
        guard let process = clashProcess else {
            processLock.unlock()
            reply(true, nil)
            return
        }
        
        guard process.isRunning else {
            clashProcess = nil
            clashProcessPID = 0
            processLock.unlock()
            reply(true, nil)
            return
        }
        processLock.unlock()
        
        process.terminate()
        
        DispatchQueue.global().async { [weak self] in
            var waited = 0
            while process.isRunning && waited < 20 {
                Thread.sleep(forTimeInterval: 0.1)
                waited += 1
            }
            
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            
            self?.processLock.lock()
            self?.clashProcess = nil
            self?.clashProcessPID = 0
            self?.processLock.unlock()
            
            reply(true, nil)
        }
    }
    
    func isClashCoreRunning(withReply reply: @escaping (Bool, Int32) -> Void) {
        processLock.lock()
        defer { processLock.unlock() }
        
        if let process = clashProcess {
            if process.isRunning {
                reply(true, process.processIdentifier)
            } else {
                clashProcess = nil
                clashProcessPID = 0
                reply(false, 0)
            }
        } else {
            reply(false, 0)
        }
    }
    
    func runPrivilegedCommand(command: String, arguments: [String], withReply reply: @escaping (Bool, String?, String?) -> Void) {
        guard allowedCommands.contains(command) else {
            reply(false, nil, "Command not allowed: \(command)")
            return
        }
        
        guard FileManager.default.fileExists(atPath: command) else {
            reply(false, nil, "Command not found: \(command)")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        DispatchQueue.global().async {
            do {
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if process.terminationStatus == 0 {
                    reply(true, output, nil)
                } else {
                    reply(false, output, errorOutput)
                }
            } catch {
                reply(false, nil, error.localizedDescription)
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
    
    private func runNetworkSetup(_ arguments: [String]) -> (success: Bool, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return (false, errorString)
            }
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
