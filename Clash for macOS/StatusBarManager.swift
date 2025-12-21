import AppKit
import Combine
import SwiftUI

class LayoutSafeHostingView<Content: View>: NSView {
    private var hostingView: NSHostingView<Content>

    init(rootView: Content) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
    }
}

class StatusBarManager: NSObject, ObservableObject {
    static let shared = StatusBarManager()

    private var statusItem: NSStatusItem?
    private var proxiesTask: Task<Void, Never>?
    private var speedUpdateTimer: Timer?

    @Published var uploadSpeed: Int64 = 0
    @Published var downloadSpeed: Int64 = 0
    @Published var showSpeed: Bool = AppSettings.shared.showSpeedInStatusBar

    private var proxyMode: String = "rule"
    private var proxyGroups: [ProxyGroupInfo] = []

    private var dataService: ClashDataService { ClashDataService.shared }

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
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            if AppSettings.shared.showMenuBarIcon {
                if self.statusItem == nil {
                    self.createStatusItem()
                }
                self.showSpeed = AppSettings.shared.showSpeedInStatusBar
            } else {
                self.removeStatusItem()
            }
        }
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        if let button = statusItem?.button {
            let view = LayoutSafeHostingView(
                rootView: StatusBarView(manager: self)
            )
            view.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(view)

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: button.topAnchor),
                view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            ])
        }

        updateMenu()
        startSpeedSync()
        refreshProxyData()
    }

    private func removeStatusItem() {
        stopSpeedSync()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private var statusBarHeight: CGFloat {
        NSStatusBar.system.thickness
    }

    var iconSize: CGFloat {
        max(12, statusBarHeight * 0.7)
    }

    var fontSize: CGFloat {
        max(7, statusBarHeight * 0.4)
    }

    func formatSpeedShort(_ bytesPerSecond: Int64) -> String {
        let kb = Double(bytesPerSecond) / 1024
        let mb = kb / 1024

        if mb >= 10 {
            return String(format: "%4.0fM", mb)
        } else if mb >= 1 {
            return String(format: "%4.1fM", mb)
        } else if kb >= 10 {
            return String(format: "%4.0fK", kb)
        } else if kb >= 1 {
            return String(format: "%4.1fK", kb)
        } else {
            return String(format: "%4dB", bytesPerSecond)
        }
    }

    private func startSpeedSync() {
        speedUpdateTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.uploadSpeed = self.dataService.uploadSpeed
                self.downloadSpeed = self.dataService.downloadSpeed
            }
        }
    }

    private func stopSpeedSync() {
        speedUpdateTimer?.invalidate()
        speedUpdateTimer = nil
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
                    .map {
                        ProxyGroupInfo(
                            name: $0.name,
                            type: $0.type,
                            now: $0.now,
                            all: $0.all ?? []
                        )
                    }

                await MainActor.run {
                    self?.proxyGroups = groups
                    self?.updateMenu()
                }
            } catch {
            }
        }
    }

    private func isProxyGroup(_ type: String) -> Bool {
        ["Selector", "URLTest", "Fallback", "LoadBalance", "Relay"].contains(
            type
        )
    }

    private func updateMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open Main Window",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let systemProxyItem = NSMenuItem(
            title: "System Proxy",
            action: #selector(toggleSystemProxy),
            keyEquivalent: ""
        )
        systemProxyItem.target = self
        systemProxyItem.state = AppSettings.shared.systemProxy ? .on : .off
        menu.addItem(systemProxyItem)

        let tunItem = NSMenuItem(
            title: "TUN Mode",
            action: #selector(toggleTunMode),
            keyEquivalent: ""
        )
        tunItem.target = self
        tunItem.state = AppSettings.shared.tunMode ? .on : .off
        let helperInstalled = HelperManager.shared.isHelperInstalled
        let serviceEnabled = AppSettings.shared.serviceMode
        tunItem.isEnabled = helperInstalled && serviceEnabled
        menu.addItem(tunItem)

        menu.addItem(NSMenuItem.separator())

        let modes = [
            ("Global", "global"), ("Rule", "rule"), ("Direct", "direct"),
        ]
        for (title, mode) in modes {
            let modeItem = NSMenuItem(
                title: title,
                action: #selector(selectProxyMode(_:)),
                keyEquivalent: ""
            )
            modeItem.target = self
            modeItem.representedObject = mode
            modeItem.state = proxyMode == mode ? .on : .off
            menu.addItem(modeItem)
        }

        menu.addItem(NSMenuItem.separator())

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
            let emptyItem = NSMenuItem(
                title: "No proxy groups",
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            proxiesMenu.addItem(emptyItem)
        } else {
            for group in filteredGroups {
                let groupMenu = NSMenu()
                for proxyName in group.all {
                    let proxyItem = NSMenuItem(
                        title: proxyName,
                        action: #selector(selectProxy(_:)),
                        keyEquivalent: ""
                    )
                    proxyItem.target = self
                    proxyItem.representedObject = [
                        "group": group.name, "proxy": proxyName,
                    ]
                    proxyItem.state = group.now == proxyName ? .on : .off
                    let isSelectable = group.type == "Selector"
                    proxyItem.isEnabled = isSelectable
                    groupMenu.addItem(proxyItem)
                }

                let groupItem = NSMenuItem(
                    title: group.name,
                    action: nil,
                    keyEquivalent: ""
                )
                groupItem.submenu = groupMenu
                proxiesMenu.addItem(groupItem)
            }
        }
        let proxiesMenuItem = NSMenuItem(
            title: "Proxies",
            action: nil,
            keyEquivalent: ""
        )
        proxiesMenuItem.submenu = proxiesMenu
        menu.addItem(proxiesMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openMainWindow() {
        AppDelegate.shared?.showMainWindow()
    }

    @objc private func toggleSystemProxy() {
        let settings = AppSettings.shared
        settings.systemProxy.toggle()
        SystemProxyManager.shared.toggleSystemProxy(
            enabled: settings.systemProxy
        )
        updateMenu()
    }

    @objc private func toggleTunMode() {
        let settings = AppSettings.shared
        settings.tunMode.toggle()
        ConfigurationManager.shared.syncConfiguration()
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
            let proxy = info["proxy"]
        else { return }

        Task {
            do {
                try await ClashAPI.shared.selectProxy(
                    selectorName: group,
                    proxyName: proxy
                )
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

struct StatusBarView: View {
    @ObservedObject var manager: StatusBarManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "network")
                .font(.system(size: manager.iconSize, weight: .medium))

            if manager.showSpeed {
                VStack(alignment: .leading, spacing: 0) {
                    Text("↑ \(manager.formatSpeedShort(manager.uploadSpeed))")
                    Text("↓ \(manager.formatSpeedShort(manager.downloadSpeed))")
                }
                .font(
                    .system(
                        size: manager.fontSize,
                        weight: .regular,
                        design: .monospaced
                    )
                )
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
        .allowsHitTesting(false)
    }
}
