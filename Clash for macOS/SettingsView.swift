import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsHeader(title: "Settings")
                
                SystemSettingsView(settings: settings)
                
                ClashSettingsView(settings: settings)
                
                CoreManagementView()
                
                ServiceModeSettingsView(settings: settings)
                
                AppearanceSettingsView(settings: settings)
                
                AdvancedSettingsView(settings: settings)
                
                ActionsSettingsView(settings: settings)
                
                AboutSettingsView()
                
                Spacer()
            }
            .padding(30)
        }
    }
}


struct SystemSettingsView: View {
    @Bindable var settings: AppSettings
    
    var body: some View {
        SettingsSection(title: "System", icon: "desktopcomputer") {
            VStack(spacing: 16) {
                SettingsRow(title: "Start with macOS", subtitle: "Launch at login") {
                    Toggle("", isOn: $settings.startAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "Silent Start", subtitle: "Start minimized") {
                    Toggle("", isOn: $settings.silentStart)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider().background(Color.gray.opacity(0.3))

                SettingsRow(title: "Menu Bar Icon", subtitle: "Show Clash icon in menu bar") {
                    Toggle("", isOn: $settings.showMenuBarIcon)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider().background(Color.gray.opacity(0.3))

                SettingsRow(title: "Show Speed in Menu Bar", subtitle: "Display upload/download speed") {
                    Toggle("", isOn: $settings.showSpeedInStatusBar)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!settings.showMenuBarIcon)
                }

            }
        }
    }
}

struct ClashSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var showSecret = false
    private var proxyManager = SystemProxyManager.shared
    private var helperManager = HelperManager.shared
    
    init(settings: AppSettings) {
        self.settings = settings
    }
    
    private var tunModeSubtitle: String {
        if !helperManager.isHelperInstalled {
            return "Requires Service Mode to be installed"
        } else if !settings.serviceMode {
            return "Requires Service Mode to be enabled"
        }
        return "Enable TUN device for traffic"
    }
    
    private func reloadConfigIfRunning() {
        if let selectedId = ProfileManager.shared.selectedProfileId,
           let profile = ProfileManager.shared.profiles.first(where: { $0.id == selectedId }) {
            ProfileManager.shared.applyProfile(profile)
        } else {
            try? FileManager.default.removeItem(at: ClashCoreManager.shared.configPath)
            ClashCoreManager.shared.reloadConfigViaAPI()
        }
    }
    
    var body: some View {
        SettingsSection(title: "Clash", icon: "network") {
            VStack(spacing: 16) {
                SettingsRow(title: "System Proxy", subtitle: "Enable system-wide proxy") {
                    Toggle("", isOn: Binding(
                        get: { settings.systemProxy },
                        set: { newValue in
                            settings.systemProxy = newValue
                            proxyManager.toggleSystemProxy(enabled: newValue)
                        }
                    ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Divider().background(Color.gray.opacity(0.3))

                SettingsRow(title: "Bypass System Proxy", subtitle: "Bypass proxy for local addresses") {
                    Toggle("", isOn: $settings.bypassSystemProxy)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                if settings.bypassSystemProxy {
                    SettingsRow(title: "Bypass List", subtitle: "Domains and IPs to ignore") {
                        TextField("", text: $settings.bypassDomains)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .frame(width: 300)
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(
                    title: "TUN Mode",
                    subtitle: tunModeSubtitle
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.tunMode },
                        set: { newValue in
                            settings.tunMode = newValue
                            reloadConfigIfRunning()
                        }
                    ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!helperManager.isHelperInstalled || !settings.serviceMode)
                }
                
                if settings.tunMode {
                    Group {
                        SettingsRow(title: "  Stack", subtitle: "TUN interface stack") {
                            Picker("", selection: Binding(
                                get: { settings.tunStack },
                                set: { newValue in
                                    settings.tunStack = newValue
                                    reloadConfigIfRunning()
                                }
                            )) {
                                ForEach(TunStackMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 100)
                        }
                        
                        SettingsRow(title: "  DNS Hijack", subtitle: "DNS hijack rules") {
                            TextField("", text: Binding(
                                get: { settings.tunDnsHijack },
                                set: { newValue in
                                    settings.tunDnsHijack = newValue
                                    reloadConfigIfRunning()
                                }
                            ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                                .frame(width: 160)
                        }
                        
                        SettingsRow(title: "  Auto Route", subtitle: "Add default route") {
                            Toggle("", isOn: Binding(
                                get: { settings.tunAutoRoute },
                                set: { newValue in
                                    settings.tunAutoRoute = newValue
                                    reloadConfigIfRunning()
                                }
                            ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        SettingsRow(title: "  Auto Detect Interface", subtitle: "Auto detect interface") {
                            Toggle("", isOn: Binding(
                                get: { settings.tunAutoDetectInterface },
                                set: { newValue in
                                    settings.tunAutoDetectInterface = newValue
                                    reloadConfigIfRunning()
                                }
                            ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "Allow LAN", subtitle: "Allow connections from LAN") {
                    Toggle("", isOn: Binding(
                        get: { settings.allowLAN },
                        set: { newValue in
                            settings.allowLAN = newValue
                            ClashCoreManager.shared.updateConfigViaAPI(params: ["allow-lan": newValue])
                        }
                    ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "IPv6", subtitle: "Enable IPv6 support") {
                    Toggle("", isOn: Binding(
                        get: { settings.ipv6 },
                        set: { newValue in
                            settings.ipv6 = newValue
                            ClashCoreManager.shared.updateConfigViaAPI(params: ["ipv6": newValue])
                        }
                    ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "Mixed Port", subtitle: "HTTP/SOCKS5 mixed proxy port") {
                    TextField("", text: $settings.mixedPort)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .frame(width: 80)
                        .onChange(of: settings.mixedPort) { oldValue, newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue {
                                settings.mixedPort = filtered
                            }
                            if let port = Int(filtered), (port < 1 || port > 65535) {
                                settings.mixedPort = oldValue
                            }
                        }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "HTTP Port", subtitle: "HTTP proxy port") {
                    TextField("", text: $settings.httpPort)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .frame(width: 80)
                        .onChange(of: settings.httpPort) { oldValue, newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue {
                                settings.httpPort = filtered
                            }
                            if let port = Int(filtered), (port < 1 || port > 65535) {
                                settings.httpPort = oldValue
                            }
                        }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "SOCKS5 Port", subtitle: "SOCKS5 proxy port") {
                    TextField("", text: $settings.socksPort)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .frame(width: 80)
                        .onChange(of: settings.socksPort) { oldValue, newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue {
                                settings.socksPort = filtered
                            }
                            if let port = Int(filtered), (port < 1 || port > 65535) {
                                settings.socksPort = oldValue
                            }
                        }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "External Controller", subtitle: "RESTful API endpoint") {
                    TextField("", text: $settings.externalController)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .frame(width: 160)
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "Secret", subtitle: "API authentication secret") {
                    HStack(spacing: 8) {
                        if showSecret {
                            TextField("", text: $settings.secret)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                                .frame(width: 140)
                        } else {
                            SecureField("", text: $settings.secret)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                                .frame(width: 140)
                        }
                        
                        Button(action: { showSecret.toggle() }) {
                            Image(systemName: showSecret ? "eye.slash" : "eye")
                                .foregroundStyle(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "Auto Update GeoIP", subtitle: "Automatically update GeoIP database") {
                    Toggle("", isOn: $settings.autoUpdateGeoIP)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "GeoIP URL", subtitle: "Country.mmdb download source") {
                    TextField("", text: $settings.geoIPUrl)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .frame(width: 300)
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "GeoSite URL", subtitle: "geosite.dat download source") {
                    TextField("", text: $settings.geoSiteUrl)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .frame(width: 300)
                }
            }
        }
    }
}


struct AppearanceSettingsView: View {
    @Bindable var settings: AppSettings
    
    var body: some View {
        SettingsSection(title: "Appearance", icon: "paintbrush.fill") {
            VStack(spacing: 16) {
                SettingsRow(title: "Theme", subtitle: "Choose your preferred appearance") {
                    Picker("", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
    }
}

struct AdvancedSettingsView: View {
    @Bindable var settings: AppSettings
    
    var body: some View {
        SettingsSection(title: "Advanced", icon: "gearshape.2.fill") {
            VStack(spacing: 16) {
                SettingsRow(title: "Log Level", subtitle: "Minimum log level to display") {
                    Picker("", selection: Binding(
                        get: { settings.logLevel },
                        set: { newValue in
                            settings.logLevel = newValue
                            ClashCoreManager.shared.updateConfigViaAPI(params: ["log-level": newValue.rawValue.lowercased()])
                        }
                    )) {
                        ForEach(LogLevelSetting.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
        }
    }
}

struct ActionsSettingsView: View {
    @Bindable var settings: AppSettings
    var geoManager = GeoIPManager.shared
    
    var body: some View {
        SettingsSection(title: "Actions", icon: "bolt.fill") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ActionButton(title: "Reload Config", icon: "arrow.clockwise", color: .blue) {
                        ClashCoreManager.shared.reloadConfigViaAPI()
                    }
                    
                    ActionButton(
                        title: geoManager.isDownloading ? "Downloading..." : "Update GeoIP",
                        icon: geoManager.isDownloading ? "arrow.down.circle" : "globe",
                        color: geoManager.isDownloading ? .gray : .green
                    ) {
                        Task {
                            await geoManager.downloadAll()
                        }
                    }
                    .disabled(geoManager.isDownloading)
                    
                    ActionButton(title: "Flush DNS", icon: "network.badge.shield.half.filled", color: .orange) {
                        Task {
                            try? await ClashAPI.shared.flushFakeIPCache()
                        }
                    }
                    
                    ActionButton(title: "Reset Settings", icon: "arrow.counterclockwise", color: .red) {
                        settings.resetToDefaults()
                    }
                }
                
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Text("GeoIP:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(geoManager.geoIPLastUpdateText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(geoIPStatusColor)
                    }
                    
                    HStack(spacing: 6) {
                        Text("GeoSite:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(geoManager.geoSiteLastUpdateText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(geoSiteStatusColor)
                    }
                    
                    Spacer()
                }
            }
        }
    }
    
    private var geoIPStatusColor: Color {
        switch geoManager.geoIPStatus {
        case .notDownloaded: return .orange
        case .downloaded: return .green
        case .downloading: return .blue
        case .error: return .red
        }
    }
    
    private var geoSiteStatusColor: Color {
        switch geoManager.geoSiteStatus {
        case .notDownloaded: return .orange
        case .downloaded: return .green
        case .downloading: return .blue
        case .error: return .red
        }
    }
}


struct CoreManagementView: View {
    private var coreManager = ClashCoreManager.shared
    @State private var showDeleteConfirm = false
    
    var body: some View {
        SettingsSection(title: "Core Management", icon: "cpu") {
            VStack(spacing: 16) {
                SettingsRow(title: "Core Status", subtitle: "Clash core running state") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(coreManager.isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(coreManager.isRunning ? "Running" : "Stopped")
                            .font(.system(size: 12))
                            .foregroundStyle(coreManager.isRunning ? .green : .secondary)
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                HStack(spacing: 12) {
                    if coreManager.isRunning {
                        Button(action: { coreManager.stopCore() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.fill")
                                Text("Stop")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { coreManager.restartCore() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Restart")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: { coreManager.startCore() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Start")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isCoreInstalled ? Color.green : Color.gray)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isCoreInstalled)
                    }
                    
                    Spacer()
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "Core Type", subtitle: "Select Clash core variant") {
                    Picker("", selection: Binding(
                        get: { coreManager.currentCoreType },
                        set: { coreManager.selectCoreType($0) }
                    )) {
                        ForEach(ClashCoreType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .disabled(coreManager.isRunning)
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "Installed Version", subtitle: "Currently installed core") {
                    HStack(spacing: 8) {
                        switch coreManager.coreStatus {
                        case .notInstalled:
                            Text("Not Installed")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        case .installed(let version):
                            Text("\(coreManager.currentCoreType.displayName) \(version)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.green)
                        case .downloading(let progress):
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.blue)
                            }
                        case .error(let message):
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await coreManager.downloadCore()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: coreManager.isDownloading ? "arrow.down.circle" : (isCoreInstalled ? "arrow.clockwise" : "arrow.down.to.line"))
                            Text(coreManager.isDownloading ? "Downloading..." : (isCoreInstalled ? "Update Core" : "Install Core"))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(coreManager.isDownloading || coreManager.isRunning ? Color.gray : Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(coreManager.isDownloading || coreManager.isRunning)
                    
                    if isCoreInstalled {
                        Button(action: {
                            showDeleteConfirm = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Remove")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(coreManager.isRunning ? Color.gray : Color.red)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(coreManager.isRunning)
                        .alert("Delete Core", isPresented: $showDeleteConfirm) {
                            Button("Cancel", role: .cancel) {}
                            Button("Delete", role: .destructive) {
                                try? coreManager.deleteCore()
                            }
                        } message: {
                            Text("Are you sure you want to delete the Clash core?")
                        }
                    }
                    
                    Spacer()
                }
                
            }
        }
    }
    
    private var isCoreInstalled: Bool {
        if case .installed = coreManager.coreStatus {
            return true
        }
        return false
    }
}

struct ServiceModeSettingsView: View {
    @Bindable var settings: AppSettings
    private var helperManager = HelperManager.shared
    @State private var isInstalling = false
    @State private var isUninstalling = false
    @State private var isUpdating = false
    @State private var showInstallError = false
    @State private var installErrorMessage = ""
    
    init(settings: AppSettings) {
        self.settings = settings
    }
    
    var body: some View {
        SettingsSection(title: "Service Mode", icon: "shield.checkered") {
            VStack(spacing: 16) {
                SettingsRow(title: "Enable Service Mode", subtitle: "Run Clash core with root privileges for TUN mode") {
                    Toggle("", isOn: $settings.serviceMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!helperManager.isHelperInstalled)
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "Helper Status", subtitle: "Privileged helper for system integration") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(helperManager.isHelperInstalled ? (helperManager.helperNeedsUpdate ? Color.orange : Color.green) : Color.orange)
                            .frame(width: 8, height: 8)
                        if helperManager.isHelperInstalled {
                            if helperManager.helperNeedsUpdate {
                                Text("v\(helperManager.helperVersion) → v\(helperManager.embeddedHelperVersion)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.orange)
                            } else {
                                Text("v\(helperManager.helperVersion)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                        } else {
                            Text("Not Installed")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                HStack(spacing: 12) {
                    if !helperManager.isHelperInstalled {
                        Button(action: installHelper) {
                            HStack(spacing: 6) {
                                if isInstalling {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "plus.circle")
                                }
                                Text(isInstalling ? "Installing..." : "Install Helper")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isInstalling ? Color.gray : Color.blue)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isInstalling)
                    } else {
                        if helperManager.helperNeedsUpdate {
                            Button(action: updateHelper) {
                                HStack(spacing: 6) {
                                    if isUpdating {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text(isUpdating ? "Updating..." : "Update Helper")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(isUpdating ? Color.gray : Color.blue)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isUpdating)
                        }
                        
                        Button(action: uninstallHelper) {
                            HStack(spacing: 6) {
                                if isUninstalling {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "trash")
                                }
                                Text(isUninstalling ? "Uninstalling..." : "Uninstall Helper")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isUninstalling ? Color.gray : Color.red)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isUninstalling)
                    }
                    
                    Spacer()
                }
                
                if !helperManager.isHelperInstalled {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Service mode requires installing a privileged helper. Administrator password will be required.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .alert("Installation Error", isPresented: $showInstallError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installErrorMessage)
        }
    }
    
    private func installHelper() {
        isInstalling = true
        
        helperManager.installHelper { success, error in
            isInstalling = false
            if !success {
                installErrorMessage = error ?? "Unknown error"
                showInstallError = true
            }
        }
    }
    
    private func uninstallHelper() {
        isUninstalling = true
        settings.serviceMode = false
        
        helperManager.uninstallHelper { success, error in
            isUninstalling = false
            if !success {
                installErrorMessage = error ?? "Unknown error"
                showInstallError = true
            }
        }
    }
    
    private func updateHelper() {
        isUpdating = true
        
        helperManager.updateHelper { success, error in
            isUpdating = false
            if !success {
                installErrorMessage = error ?? "Unknown error"
                showInstallError = true
            }
        }
    }
}

struct AboutSettingsView: View {
    var coreManager = ClashCoreManager.shared
    var geoManager = GeoIPManager.shared
    
    var body: some View {
        SettingsSection(title: "About", icon: "info.circle.fill") {
            VStack(spacing: 12) {
                HStack {
                    Text("Clash for macOS")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                        .foregroundStyle(.secondary)
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                HStack {
                    Text("Clash Core")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(coreVersionText)
                        .foregroundStyle(.secondary)
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                HStack {
                    Text("GeoIP Database")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(geoManager.geoIPLastUpdateText)
                        .foregroundStyle(.secondary)
                }

                
                Divider().background(Color.gray.opacity(0.3))
                
                HStack(spacing: 16) {
                    Link(destination: URL(string: "https://github.com/Dreamacro/clash")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("GitHub")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                    }
                    
                    Link(destination: URL(string: "https://clash.wiki")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "book")
                            Text("Documentation")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                    }
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var coreVersionText: String {
        if case .installed(let version) = coreManager.coreStatus {
            return "\(coreManager.currentCoreType.displayName) \(version)"
        }
        return "Not Installed"
    }
}


struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(width: 800, height: 700)
    }
}
