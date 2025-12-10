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
                    Toggle("", isOn: $settings.tunMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!helperManager.isHelperInstalled || !settings.serviceMode)
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "Allow LAN", subtitle: "Allow connections from LAN") {
                    Toggle("", isOn: $settings.allowLAN)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Divider().background(Color.gray.opacity(0.3))
                
                SettingsRow(title: "IPv6", subtitle: "Enable IPv6 support") {
                    Toggle("", isOn: $settings.ipv6)
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
                    Picker("", selection: $settings.logLevel) {
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
    
    var body: some View {
        SettingsSection(title: "Actions", icon: "bolt.fill") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ActionButton(title: "Reload Config", icon: "arrow.clockwise", color: .blue) {
                    }
                    
                    ActionButton(title: "Update GeoIP", icon: "globe", color: .green) {
                    }
                    
                    ActionButton(title: "Flush DNS", icon: "network.badge.shield.half.filled", color: .orange) {
                    }
                    
                    ActionButton(title: "Reset Settings", icon: "arrow.counterclockwise", color: .red) {
                        settings.resetToDefaults()
                    }
                }
            }
        }
    }
}

struct CoreManagementView: View {
    private var coreManager = ClashCoreManager.shared
    @State private var showDeleteConfirm = false
    
    var body: some View {
        SettingsSection(title: "Core Management", icon: "cpu") {
            VStack(spacing: 16) {
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
                        .background(coreManager.isDownloading ? Color.gray : Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(coreManager.isDownloading)
                    
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
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
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
                            .fill(helperManager.isHelperInstalled ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        if helperManager.isHelperInstalled {
                            Text("v\(helperManager.helperVersion)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.green)
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
}

struct AboutSettingsView: View {
    private var coreManager = ClashCoreManager.shared
    
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
                    Text("20230912")
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
