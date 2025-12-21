import SwiftUI

@Observable
class NavigationManager {
    static let shared = NavigationManager()
    var selection: NavigationItem = .general

    func navigateToSettings() {
        selection = .settings
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    static var shared: AppDelegate?

    var mainWindow: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let manager = ClashCoreManager.shared
        let wasRunning = UserDefaults.standard.bool(
            forKey: "clashCoreWasRunning"
        )
        if case .installed = manager.coreStatus, wasRunning {
            manager.startCore()
        }

        StatusBarManager.shared.setup()

        setupMainWindow()

        let settings = AppSettings.shared
        if settings.silentStart {
            if settings.showMenuBarIcon {
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    func setupMainWindow() {
        let config = WindowSizeManager.shared.getCurrentWindowConfig()
        let contentView = ContentView()
            .frame(
                minWidth: config.minWidth,
                idealWidth: config.defaultWidth,
                maxWidth: .infinity,
                minHeight: config.minHeight,
                idealHeight: config.defaultHeight,
                maxHeight: .infinity
            )

        mainWindow = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: config.defaultWidth,
                height: config.defaultHeight
            ),
            styleMask: [
                .titled, .closable, .miniaturizable, .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = "Clash for macOS"
        mainWindow.center()
        mainWindow.setFrameAutosaveName("Main Window")
        mainWindow.contentView = NSHostingView(rootView: contentView)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.tabbingMode = .disallowed
        mainWindow.delegate = self
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClashCoreManager.shared.stopCore()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if AppSettings.shared.showMenuBarIcon {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
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
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NavigationManager.shared.navigateToSettings()
                    appDelegate.showMainWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
