import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    var mainWindow: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = ClashCoreManager.shared
        let wasRunning = UserDefaults.standard.bool(forKey: "clashCoreWasRunning")
        if case .installed = manager.coreStatus, wasRunning {
            manager.startCore()
        }
        
        StatusBarManager.shared.setup()
        
        setupMainWindow()
        
        if !AppSettings.shared.silentStart {
             mainWindow.makeKeyAndOrderFront(nil)
        }
    }
    
    func setupMainWindow() {
        let config = WindowSizeManager.shared.getCurrentWindowConfig()
        let contentView = ContentView()
            .preferredColorScheme(AppSettings.shared.appearance.colorScheme)
            .frame(minWidth: config.minWidth, idealWidth: config.defaultWidth, maxWidth: .infinity, minHeight: config.minHeight, idealHeight: config.defaultHeight, maxHeight: .infinity)
        
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: config.defaultWidth, height: config.defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        mainWindow.title = "Clash for macOS"
        mainWindow.center()
        mainWindow.setFrameAutosaveName("Main Window")
        mainWindow.contentView = NSHostingView(rootView: contentView)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.delegate = self
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(ClashCoreManager.shared.isRunning, forKey: "clashCoreWasRunning")
        ClashCoreManager.shared.stopCore()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        return true
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide window instead of closing to keep app running
        sender.orderOut(nil)
        return false 
    }
}


@main
struct Clash_for_macOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var settings = AppSettings.shared

    var body: some Scene {
        Settings {
            EmptyView()
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
