import AppKit
import Combine
import SwiftUI

extension NSMenuItem {
    convenience init(
        title: String,
        action: Selector?,
        target: AnyObject?,
        keyEquivalent: String = "",
        state: NSControl.StateValue = .off,
        isEnabled: Bool = true,
        representedObject: Any? = nil
    ) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
        self.state = state
        self.isEnabled = isEnabled
        self.representedObject = representedObject
    }
}

class MenuBuilder {
    private let menu = NSMenu()
    private weak var target: AnyObject?

    init(target: AnyObject?) {
        self.target = target
    }

    @discardableResult
    func addItem(
        title: String,
        action: Selector?,
        keyEquivalent: String = "",
        state: NSControl.StateValue = .off,
        isEnabled: Bool = true,
        representedObject: Any? = nil
    ) -> Self {
        menu.addItem(NSMenuItem(
            title: title,
            action: action,
            target: target,
            keyEquivalent: keyEquivalent,
            state: state,
            isEnabled: isEnabled,
            representedObject: representedObject
        ))
        return self
    }

    @discardableResult
    func addSeparator() -> Self {
        menu.addItem(.separator())
        return self
    }

    @discardableResult
    func addSubmenu(title: String, builder: (MenuBuilder) -> Void) -> Self {
        let submenuBuilder = MenuBuilder(target: target)
        builder(submenuBuilder)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenuBuilder.build()
        menu.addItem(item)
        return self
    }

    func build() -> NSMenu {
        menu
    }
}

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
        if bytesPerSecond == 0 {
            return "0 B/s"
        }
        let kb = Double(bytesPerSecond) / 1024
        let mb = kb / 1024
        let gb = mb / 1024

        if gb >= 100 {
            return String(format: "%.0f GB/s", gb)
        } else if gb >= 10 {
            return String(format: "%.1f GB/s", gb)
        } else if gb >= 1 {
            return String(format: "%.2f GB/s", gb)
        } else if mb >= 100 {
            return String(format: "%.0f MB/s", mb)
        } else if mb >= 10 {
            return String(format: "%.1f MB/s", mb)
        } else if mb >= 1 {
            return String(format: "%.2f MB/s", mb)
        } else if kb >= 100 {
            return String(format: "%.0f KB/s", kb)
        } else if kb >= 10 {
            return String(format: "%.1f KB/s", kb)
        } else if kb >= 1 {
            return String(format: "%.2f KB/s", kb)
        } else {
            return String(format: "%lld B/s", bytesPerSecond)
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
        let settings = AppSettings.shared
        let helperInstalled = HelperManager.shared.isHelperInstalled
        let tunEnabled = helperInstalled && settings.serviceMode

        let filteredGroups: [ProxyGroupInfo] = {
            switch proxyMode {
            case "global": return proxyGroups.filter { $0.name == "GLOBAL" }
            case "direct": return []
            default: return proxyGroups.filter { $0.name != "GLOBAL" }
            }
        }()

        statusItem?.menu = MenuBuilder(target: self)
            .addItem(title: "Open Main Window", action: #selector(openMainWindow), keyEquivalent: "o")
            .addSeparator()
            .addItem(title: "System Proxy", action: #selector(toggleSystemProxy),
                     state: settings.systemProxy ? .on : .off)
            .addItem(title: "TUN Mode", action: #selector(toggleTunMode),
                     state: settings.tunMode ? .on : .off, isEnabled: tunEnabled)
            .addSeparator()
            .addItem(title: "Global", action: #selector(selectProxyMode(_:)),
                     state: proxyMode == "global" ? .on : .off, representedObject: "global")
            .addItem(title: "Rule", action: #selector(selectProxyMode(_:)),
                     state: proxyMode == "rule" ? .on : .off, representedObject: "rule")
            .addItem(title: "Direct", action: #selector(selectProxyMode(_:)),
                     state: proxyMode == "direct" ? .on : .off, representedObject: "direct")
            .addSeparator()
            .addSubmenu(title: "Proxies") { submenu in
                if filteredGroups.isEmpty {
                    submenu.addItem(title: "No proxy groups", action: nil, isEnabled: false)
                } else {
                    for group in filteredGroups {
                        submenu.addSubmenu(title: group.name) { groupMenu in
                            let isSelectable = group.type == "Selector"
                            for proxyName in group.all {
                                groupMenu.addItem(
                                    title: proxyName,
                                    action: #selector(selectProxy(_:)),
                                    state: group.now == proxyName ? .on : .off,
                                    isEnabled: isSelectable,
                                    representedObject: ["group": group.name, "proxy": proxyName]
                                )
                            }
                        }
                    }
                }
            }
            .addSeparator()
            .addItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
            .build()
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

    private var speedTextWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: manager.fontSize)
        let attributes = [NSAttributedString.Key.font: font]
        let maxWidthString = "888.8 MB/s"
        let size = (maxWidthString as NSString).size(withAttributes: attributes)
        return ceil(size.width)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "network")
                .font(.system(size: manager.iconSize, weight: .medium))

            if manager.showSpeed {
                VStack(alignment: .trailing, spacing: -2) {
                    Text("\(manager.formatSpeedShort(manager.uploadSpeed))")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("\(manager.formatSpeedShort(manager.downloadSpeed))")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: manager.fontSize))
                .frame(width: speedTextWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
        .allowsHitTesting(false)
    }
}
