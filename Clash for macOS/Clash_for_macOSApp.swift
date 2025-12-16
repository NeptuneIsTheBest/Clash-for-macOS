import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = ClashCoreManager.shared
        let wasRunning = UserDefaults.standard.bool(forKey: "clashCoreWasRunning")
        if case .installed = manager.coreStatus, wasRunning {
            manager.startCore()
        }
        
        StatusBarManager.shared.setup()
        
        if AppSettings.shared.silentStart {
            DispatchQueue.main.async {
                NSApp.windows.forEach { $0.close() }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(ClashCoreManager.shared.isRunning, forKey: "clashCoreWasRunning")
        ClashCoreManager.shared.stopCore()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
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
