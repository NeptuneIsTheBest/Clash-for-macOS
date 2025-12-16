import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = ClashCoreManager.shared
        if case .installed = manager.coreStatus {
            manager.startCore()
        }
        
        Task {
            await GeoIPManager.shared.updateIfNeeded()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        ClashCoreManager.shared.stopCore()
    }
}


@main
struct Clash_for_macOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
