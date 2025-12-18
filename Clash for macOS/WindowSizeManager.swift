import AppKit
import SwiftUI

struct WindowSizeManager {
    static let shared = WindowSizeManager()

    private let defaultMinWidth: CGFloat = 800
    private let defaultMinHeight: CGFloat = 600
    private let defaultWidth: CGFloat = 1000
    private let defaultHeight: CGFloat = 700

    struct WindowConfig {
        let minWidth: CGFloat
        let minHeight: CGFloat
        let defaultWidth: CGFloat
        let defaultHeight: CGFloat
    }

    func getCurrentWindowConfig() -> WindowConfig {
        guard let screen = NSScreen.main else {
            return WindowConfig(
                minWidth: defaultMinWidth,
                minHeight: defaultMinHeight,
                defaultWidth: defaultWidth,
                defaultHeight: defaultHeight
            )
        }

        let screenFrame = screen.visibleFrame
        let screenWidth = screenFrame.width

        let minWidth: CGFloat
        let minHeight: CGFloat
        let idealWidth: CGFloat
        let idealHeight: CGFloat

        if screenWidth >= 1920 {
            minWidth = 1000
            minHeight = 700
            idealWidth = 1200
            idealHeight = 800
        } else if screenWidth >= 1400 {
            minWidth = 900
            minHeight = 650
            idealWidth = 1100
            idealHeight = 750
        } else {
            minWidth = 800
            minHeight = 550
            idealWidth = 950
            idealHeight = 650
        }

        return WindowConfig(
            minWidth: minWidth,
            minHeight: minHeight,
            defaultWidth: idealWidth,
            defaultHeight: idealHeight
        )
    }
}
