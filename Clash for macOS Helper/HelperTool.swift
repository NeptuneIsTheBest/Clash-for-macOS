import Foundation

class HelperTool: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private var clashProcess: Process?
    private var clashProcessPID: Int32 = 0
    
    func run() {
        let listener = NSXPCListener(machServiceName: kHelperToolMachServiceName)
        listener.delegate = self
        listener.resume()
        RunLoop.current.run()
    }
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
    
    func getVersion(withReply reply: @escaping (String) -> Void) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
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
        if clashProcess != nil && clashProcess!.isRunning {
            clashProcess?.terminate()
            clashProcess?.waitUntilExit()
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-d", workingDirectory, "-f", configPath]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            clashProcess = process
            clashProcessPID = process.processIdentifier
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if process.isRunning {
                    reply(true, process.processIdentifier, nil)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    self?.clashProcess = nil
                    self?.clashProcessPID = 0
                    reply(false, 0, errorString)
                }
            }
        } catch {
            reply(false, 0, error.localizedDescription)
        }
    }
    
    func stopClashCore(withReply reply: @escaping (Bool, String?) -> Void) {
        guard let process = clashProcess, process.isRunning else {
            clashProcess = nil
            clashProcessPID = 0
            reply(true, nil)
            return
        }
        
        process.terminate()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if process.isRunning {
                process.interrupt()
            }
            self?.clashProcess = nil
            self?.clashProcessPID = 0
            reply(true, nil)
        }
    }
    
    func isClashCoreRunning(withReply reply: @escaping (Bool, Int32) -> Void) {
        if let process = clashProcess, process.isRunning {
            reply(true, process.processIdentifier)
        } else {
            clashProcess = nil
            clashProcessPID = 0
            reply(false, 0)
        }
    }
    
    func runPrivilegedCommand(command: String, arguments: [String], withReply reply: @escaping (Bool, String?, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8)
            let errorOutput = String(data: errorData, encoding: .utf8)
            
            if process.terminationStatus == 0 {
                reply(true, output, nil)
            } else {
                reply(false, output, errorOutput)
            }
        } catch {
            reply(false, nil, error.localizedDescription)
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
