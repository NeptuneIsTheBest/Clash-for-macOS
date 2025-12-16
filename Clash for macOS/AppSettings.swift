import SwiftUI

@Observable
class AppSettings {
    static let shared = AppSettings()
    
    private var skipSave = false
    
    var systemProxy = false { didSet { saveSettings() } }
    var startAtLogin = false { didSet { saveSettings() } }
    var tunMode = false { didSet { saveSettings() } }
    var tunStack: TunStackMode = .system { didSet { saveSettings() } }
    var tunDnsHijack = "any:53" { didSet { saveSettings() } }
    var tunAutoRoute = true { didSet { saveSettings() } }
    var tunAutoDetectInterface = true { didSet { saveSettings() } }
    var silentStart = false { didSet { saveSettings() } }
    var allowLAN = false { didSet { saveSettings() } }
    var ipv6 = false { didSet { saveSettings() } }
    
    var mixedPort = "7890" { didSet { saveSettings() } }
    var httpPort = "7890" { didSet { saveSettings() } }
    var socksPort = "7891" { didSet { saveSettings() } }
    
    var appearance: AppearanceMode = .system { didSet { saveSettings() } }
    var showMenuBarIcon = true { didSet { saveSettings() } }
    var showSpeedInStatusBar = false { didSet { saveSettings() } }
    
    var autoUpdateGeoIP = true { didSet { saveSettings() } }
    var geoIPUrl = "https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb" { didSet { saveSettings() } }
    var geoSiteUrl = "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" { didSet { saveSettings() } }
    
    var externalController = "127.0.0.1:9090" { didSet { saveSettings() } }
    var secret = "" { didSet { saveSettings() } }
    
    var logLevel: LogLevelSetting = .info { didSet { saveSettings() } }
    var bypassSystemProxy = true { didSet { saveSettings() } }
    var bypassDomains = "127.0.0.1, localhost, *.local, 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10, 17.0.0.0/8" { didSet { saveSettings() } }
    
    var serviceMode = false { didSet { saveSettings() } }
    
    private init() {
        loadSettings()
        if secret.isEmpty {
            generateSecret()
        }
    }
    
    func generateSecret() {
        let length = 32
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        secret = String((0..<length).map { _ in characters.randomElement()! })
    }
    
    
    func loadSettings() {
        skipSave = true
        defer { skipSave = false }
        
        let defaults = UserDefaults.standard
        
        systemProxy = defaults.bool(forKey: "systemProxy")
        startAtLogin = defaults.bool(forKey: "startAtLogin")
        tunMode = defaults.bool(forKey: "tunMode")
        if let tunStackRaw = defaults.string(forKey: "tunStack"),
           let stack = TunStackMode(rawValue: tunStackRaw) {
            tunStack = stack
        }
        tunDnsHijack = defaults.string(forKey: "tunDnsHijack") ?? "any:53"
        tunAutoRoute = defaults.object(forKey: "tunAutoRoute") as? Bool ?? true
        tunAutoDetectInterface = defaults.object(forKey: "tunAutoDetectInterface") as? Bool ?? true
        
        silentStart = defaults.bool(forKey: "silentStart")
        allowLAN = defaults.object(forKey: "allowLAN") as? Bool ?? false
        ipv6 = defaults.bool(forKey: "ipv6")
        
        mixedPort = defaults.string(forKey: "mixedPort") ?? "7890"
        httpPort = defaults.string(forKey: "httpPort") ?? "7890"
        socksPort = defaults.string(forKey: "socksPort") ?? "7891"
        
        if let appearanceRaw = defaults.string(forKey: "appearance"),
           let mode = AppearanceMode(rawValue: appearanceRaw) {
            appearance = mode
        }
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        showSpeedInStatusBar = defaults.bool(forKey: "showSpeedInStatusBar")
        
        autoUpdateGeoIP = defaults.object(forKey: "autoUpdateGeoIP") as? Bool ?? true
        geoIPUrl = defaults.string(forKey: "geoIPUrl") ?? "https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb"
        geoSiteUrl = defaults.string(forKey: "geoSiteUrl") ?? "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
        
        externalController = defaults.string(forKey: "externalController") ?? "127.0.0.1:9090"
        secret = defaults.string(forKey: "secret") ?? ""
        
        if let logLevelRaw = defaults.string(forKey: "logLevel"),
           let level = LogLevelSetting(rawValue: logLevelRaw) {
            logLevel = level
        }
        bypassSystemProxy = defaults.object(forKey: "bypassSystemProxy") as? Bool ?? true
        bypassDomains = defaults.string(forKey: "bypassDomains") ?? "127.0.0.1, localhost, *.local, 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10, 17.0.0.0/8"
        
        serviceMode = defaults.bool(forKey: "serviceMode")
    }
    
    func saveSettings() {
        guard !skipSave else { return }
        
        let defaults = UserDefaults.standard
        
        defaults.set(systemProxy, forKey: "systemProxy")
        defaults.set(startAtLogin, forKey: "startAtLogin")
        defaults.set(tunMode, forKey: "tunMode")
        defaults.set(tunStack.rawValue, forKey: "tunStack")
        defaults.set(tunDnsHijack, forKey: "tunDnsHijack")
        defaults.set(tunAutoRoute, forKey: "tunAutoRoute")
        defaults.set(tunAutoDetectInterface, forKey: "tunAutoDetectInterface")
        
        defaults.set(silentStart, forKey: "silentStart")
        defaults.set(allowLAN, forKey: "allowLAN")
        defaults.set(ipv6, forKey: "ipv6")
        
        defaults.set(mixedPort, forKey: "mixedPort")
        defaults.set(httpPort, forKey: "httpPort")
        defaults.set(socksPort, forKey: "socksPort")
        
        defaults.set(appearance.rawValue, forKey: "appearance")
        defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        defaults.set(showSpeedInStatusBar, forKey: "showSpeedInStatusBar")
        
        defaults.set(autoUpdateGeoIP, forKey: "autoUpdateGeoIP")
        defaults.set(geoIPUrl, forKey: "geoIPUrl")
        defaults.set(geoSiteUrl, forKey: "geoSiteUrl")
        
        defaults.set(externalController, forKey: "externalController")
        defaults.set(secret, forKey: "secret")
        
        defaults.set(logLevel.rawValue, forKey: "logLevel")
        defaults.set(bypassSystemProxy, forKey: "bypassSystemProxy")
        defaults.set(bypassDomains, forKey: "bypassDomains")
        
        defaults.set(serviceMode, forKey: "serviceMode")
    }
    
    func resetToDefaults() {
        skipSave = true
        
        systemProxy = false
        startAtLogin = false
        tunMode = false
        tunStack = .system
        tunDnsHijack = "any:53"
        tunAutoRoute = true
        tunAutoDetectInterface = true
        
        silentStart = false
        allowLAN = false
        ipv6 = false
        
        mixedPort = "7890"
        httpPort = "7890"
        socksPort = "7891"
        
        appearance = .system
        showMenuBarIcon = true
        showSpeedInStatusBar = false
        
        autoUpdateGeoIP = true
        geoIPUrl = "https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb"
        geoSiteUrl = "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
        
        externalController = "127.0.0.1:9090"
        generateSecret()
        
        logLevel = .info
        bypassSystemProxy = true
        bypassDomains = "127.0.0.1, localhost, *.local, 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10, 17.0.0.0/8"
        
        serviceMode = false
        
        skipSave = false
        saveSettings()
    }
}


enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

enum LogLevelSetting: String, CaseIterable {
    case debug = "Debug"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    case silent = "Silent"
}
