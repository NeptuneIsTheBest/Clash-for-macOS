import SwiftUI

struct GeneralView: View {
    @Bindable private var settings = AppSettings.shared
    private var coreManager = ClashCoreManager.shared
    private var proxyManager = SystemProxyManager.shared
    private var helperManager = HelperManager.shared
    private var dataService: ClashDataService { ClashDataService.shared }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsHeader(title: "General")
                
                SettingsSection(title: "Status", icon: "bolt.fill") {
                    HStack(spacing: 20) {
                        StatusCard(
                            title: "System Proxy",
                            value: settings.systemProxy ? "Enabled" : "Disabled",
                            icon: "network",
                            color: settings.systemProxy ? .green : .gray
                        ) {
                            settings.systemProxy.toggle()
                            proxyManager.toggleSystemProxy(enabled: settings.systemProxy)
                        }
                        
                        StatusCard(
                            title: "TUN Mode",
                            value: settings.tunMode ? "Enabled" : "Disabled",
                            icon: "shield.fill",
                            color: settings.tunMode ? .blue : .gray,
                            isDisabled: !helperManager.isHelperInstalled || !settings.serviceMode
                        ) {
                            settings.tunMode.toggle()
                        }
                        
                        StatusCard(
                            title: "Allow LAN",
                            value: settings.allowLAN ? "Enabled" : "Disabled",
                            icon: "wifi",
                            color: settings.allowLAN ? .orange : .gray
                        ) {
                            settings.allowLAN.toggle()
                        }
                    }
                }
                
                SettingsSection(title: "Traffic", icon: "arrow.up.arrow.down") {
                    HStack(spacing: 20) {
                        TrafficCard(
                            title: "Upload",
                            speed: formatSpeed(dataService.uploadSpeed),
                            icon: "arrow.up.circle.fill",
                            color: .green
                        )
                        
                        TrafficCard(
                            title: "Download",
                            speed: formatSpeed(dataService.downloadSpeed),
                            icon: "arrow.down.circle.fill",
                            color: .blue
                        )
                        
                        TrafficCard(
                            title: "Connections",
                            speed: "\(dataService.activeConnections)",
                            icon: "link",
                            color: .purple
                        )
                        
                        TrafficCard(
                            title: "Memory",
                            speed: ByteUtils.format(dataService.memoryUsage),
                            icon: "memorychip.fill",
                            color: .orange
                        )
                    }
                }
                
                SettingsSection(title: "Quick Info", icon: "info.circle") {
                    VStack(spacing: 12) {
                        InfoRow(label: "Mixed Port", value: settings.mixedPort)
                        Divider().background(Color.gray.opacity(0.3))
                        InfoRow(label: "HTTP Port", value: settings.httpPort)
                        Divider().background(Color.gray.opacity(0.3))
                        InfoRow(label: "SOCKS5 Port", value: settings.socksPort)
                        Divider().background(Color.gray.opacity(0.3))
                        InfoRow(label: "External Controller", value: settings.externalController)
                        Divider().background(Color.gray.opacity(0.3))
                        InfoRow(label: "Clash Core", value: coreVersionText)
                    }
                }
                
                Spacer()
            }
            .padding(30)
        }
    }
    
    private var coreVersionText: String {
        if case .installed(let version) = coreManager.coreStatus {
            return "\(coreManager.currentCoreType.displayName) \(version)"
        }
        return "Not Installed"
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var isDisabled: Bool = false
    let action: () -> Void
    
    private var displayColor: Color {
        isDisabled ? .gray : color
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(displayColor)
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(isDisabled ? "Unavailable" : value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(displayColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(displayColor.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct TrafficCard: View {
    let title: String
    let speed: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(speed)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(10)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    GeneralView()
        .frame(width: 800, height: 600)
}

