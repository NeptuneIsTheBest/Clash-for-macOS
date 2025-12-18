import Foundation

@objc(HelperProtocol)
protocol HelperProtocol {
    func getVersion(withReply reply: @escaping (String) -> Void)

    func setSystemProxy(
        host: String,
        httpPort: String,
        socksPort: String,
        bypassDomains: String,
        withReply reply: @escaping (Bool, String?) -> Void
    )

    func clearSystemProxy(withReply reply: @escaping (Bool, String?) -> Void)

    func startClashCore(
        executablePath: String,
        configPath: String,
        workingDirectory: String,
        withReply reply: @escaping (Bool, Int32, String?) -> Void
    )

    func stopClashCore(withReply reply: @escaping (Bool, String?) -> Void)

    func isClashCoreRunning(withReply reply: @escaping (Bool, Int32) -> Void)

    func runPrivilegedCommand(
        command: String,
        arguments: [String],
        withReply reply: @escaping (Bool, String?, String?) -> Void
    )
}

let kHelperToolMachServiceName = "com.neptuneisthebest.Clash-for-macOS-Helper"
