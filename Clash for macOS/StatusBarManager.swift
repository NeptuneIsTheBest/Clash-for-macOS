import AppKit
import SwiftUI

class StatusBarManager: NSObject {
    static let shared = StatusBarManager()
    
    private var statusItem: NSStatusItem?
    private var trafficTask: Task<Void, Never>?
    private var proxiesTask: Task<Void, Never>?
    
    private var uploadSpeed: Int64 = 0
    private var downloadSpeed: Int64 = 0
    
    private var proxyMode: String = "rule"
    private var proxyGroups: [ProxyGroupInfo] = []
    
    struct ProxyGroupInfo {
        let name: String
        let type: String
        let now: String?
        let all: [String]
    }
    
    private override init() {
        super.init()
    }
    
    func setup() {
        if AppSettings.shared.showMenuBarIcon {
            createStatusItem()
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    @objc private func settingsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if AppSettings.shared.showMenuBarIcon {
                if self.statusItem == nil {
                    self.createStatusItem()
                }
                self.updateSpeedDisplay()
            } else {
                self.removeStatusItem()
            }
        }
    }
    
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            updateButtonTitle(button)
        }
        
        updateMenu()
        startTrafficMonitoring()
        refreshProxyData()
    }
    
    private func removeStatusItem() {
        stopTrafficMonitoring()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    private func createStatusIcon() -> NSImage? {
        let image = NSImage(systemSymbolName: "network", accessibilityDescription: "Clash")
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        return image?.withSymbolConfiguration(config)
    }

    private func updateButtonTitle(_ button: NSStatusBarButton) {
        let settings = AppSettings.shared
        
        // Always set the icon
        button.image = createStatusIcon()
        button.image?.isTemplate = true
        
        if settings.showSpeedInStatusBar && (uploadSpeed > 0 || downloadSpeed > 0) {
            let upStr = formatSpeedShort(uploadSpeed)
            let downStr = formatSpeedShort(downloadSpeed)
            
            // Set font for better readability
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let title = NSAttributedString(string: " ↑\(upStr) ↓\(downStr)", attributes: attributes)
            
            button.attributedTitle = title
            button.imagePosition = .imageLeft
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }
    
    private func formatSpeedShort(_ bytesPerSecond: Int64) -> String {
        if bytesPerSecond == 0 {
            return "0B"
        }
        let kb = Double(bytesPerSecond) / 1024
        let mb = kb / 1024
        
        if mb >= 1 {
            return String(format: "%.1fM", mb)
        } else if kb >= 1 {
            return String(format: "%.0fK", kb)
        } else {
            return "\(bytesPerSecond)B"
        }
    }
    
    private func updateSpeedDisplay() {
        guard let button = statusItem?.button else { return }
        updateButtonTitle(button)
    }
    
    private func startTrafficMonitoring() {
        trafficTask = Task { [weak self] in
            do {
                let stream = ClashAPI.shared.getTrafficStream()
                for try await traffic in stream {
                    await MainActor.run {
                        self?.uploadSpeed = traffic.up
                        self?.downloadSpeed = traffic.down
                        self?.updateSpeedDisplay()
                    }
                }
            } catch {
            }
        }
    }
    
    private func stopTrafficMonitoring() {
        trafficTask?.cancel()
        trafficTask = nil
    }
    
    func refreshProxyData() {
        proxiesTask?.cancel()
        proxiesTask = Task { [weak self] in
            do {
                let configs = try await ClashAPI.shared.getConfigs()
                if case .string(let mode) = configs["mode"] {
                    await MainActor.run {
                        self?.proxyMode = mode.lowercased()
                    }
                }
                
                let proxies = try await ClashAPI.shared.getProxies()
                let groups = proxies.values
                    .filter { self?.isProxyGroup($0.type) ?? false }
                    .sorted { $0.name < $1.name }
                    .map { ProxyGroupInfo(name: $0.name, type: $0.type, now: $0.now, all: $0.all ?? []) }
                
                await MainActor.run {
                    self?.proxyGroups = groups
                    self?.updateMenu()
                }
            } catch {
            }
        }
    }
    
    private func isProxyGroup(_ type: String) -> Bool {
        ["Selector", "URLTest", "Fallback", "LoadBalance", "Relay"].contains(type)
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        let openItem = NSMenuItem(title: "Open Main Window", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let systemProxyItem = NSMenuItem(title: "System Proxy", action: #selector(toggleSystemProxy), keyEquivalent: "")
        systemProxyItem.target = self
        systemProxyItem.state = AppSettings.shared.systemProxy ? .on : .off
        menu.addItem(systemProxyItem)
        
        let tunItem = NSMenuItem(title: "TUN Mode", action: #selector(toggleTunMode), keyEquivalent: "")
        tunItem.target = self
        tunItem.state = AppSettings.shared.tunMode ? .on : .off
        let helperInstalled = HelperManager.shared.isHelperInstalled
        let serviceEnabled = AppSettings.shared.serviceMode
        tunItem.isEnabled = helperInstalled && serviceEnabled
        menu.addItem(tunItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let modeMenu = NSMenu()
        let modes = [("Global", "global"), ("Rule", "rule"), ("Direct", "direct")]
        for (title, mode) in modes {
            let modeItem = NSMenuItem(title: title, action: #selector(selectProxyMode(_:)), keyEquivalent: "")
            modeItem.target = self
            modeItem.representedObject = mode
            modeItem.state = proxyMode == mode ? .on : .off
            modeMenu.addItem(modeItem)
        }
        let modeMenuItem = NSMenuItem(title: "Proxy Mode", action: nil, keyEquivalent: "")
        modeMenuItem.submenu = modeMenu
        menu.addItem(modeMenuItem)
        
        let proxiesMenu = NSMenu()
        let filteredGroups: [ProxyGroupInfo]
        switch proxyMode {
        case "global":
            filteredGroups = proxyGroups.filter { $0.name == "GLOBAL" }
        case "direct":
            filteredGroups = []
        default:
            filteredGroups = proxyGroups.filter { $0.name != "GLOBAL" }
        }
        
        if filteredGroups.isEmpty {
            let emptyItem = NSMenuItem(title: "No proxy groups", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            proxiesMenu.addItem(emptyItem)
        } else {
            for group in filteredGroups {
                let groupMenu = NSMenu()
                for proxyName in group.all {
                    let proxyItem = NSMenuItem(title: proxyName, action: #selector(selectProxy(_:)), keyEquivalent: "")
                    proxyItem.target = self
                    proxyItem.representedObject = ["group": group.name, "proxy": proxyName]
                    proxyItem.state = group.now == proxyName ? .on : .off
                    let isSelectable = group.type == "Selector"
                    proxyItem.isEnabled = isSelectable
                    groupMenu.addItem(proxyItem)
                }
                
                let groupItem = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
                groupItem.submenu = groupMenu
                proxiesMenu.addItem(groupItem)
            }
        }
        let proxiesMenuItem = NSMenuItem(title: "Proxies", action: nil, keyEquivalent: "")
        proxiesMenuItem.submenu = proxiesMenu
        menu.addItem(proxiesMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible || $0.isMiniaturized }) {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func toggleSystemProxy() {
        let settings = AppSettings.shared
        settings.systemProxy.toggle()
        SystemProxyManager.shared.toggleSystemProxy(enabled: settings.systemProxy)
        updateMenu()
    }
    
    @objc private func toggleTunMode() {
        let settings = AppSettings.shared
        settings.tunMode.toggle()
        
        if let selectedId = ProfileManager.shared.selectedProfileId,
           let profile = ProfileManager.shared.profiles.first(where: { $0.id == selectedId }) {
            ProfileManager.shared.applyProfile(profile)
        } else {
            try? FileManager.default.removeItem(at: ClashCoreManager.shared.configPath)
            ClashCoreManager.shared.reloadConfigViaAPI()
        }
        updateMenu()
    }
    
    @objc private func selectProxyMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        
        Task {
            do {
                try await ClashAPI.shared.updateConfigs(params: ["mode": mode])
                await MainActor.run {
                    self.proxyMode = mode
                    self.updateMenu()
                    self.refreshProxyData()
                }
            } catch {
            }
        }
    }
    
    @objc private func selectProxy(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let group = info["group"],
              let proxy = info["proxy"] else { return }
        
        Task {
            do {
                try await ClashAPI.shared.selectProxy(selectorName: group, proxyName: proxy)
                await MainActor.run {
                    self.refreshProxyData()
                }
            } catch {
            }
        }
    }
    
    @objc private func quitApp() {
        ClashCoreManager.shared.stopCore()
        NSApplication.shared.terminate(nil)
    }
}
