import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders alongside LSUIElement in Info.plist
        NSApp.setActivationPolicy(.accessory)

        BreakScheduler.shared.registerSleepWakeObservers()
        OverlayManager.shared.registerScreenObserver()

        // Prompt for Accessibility permission (required for CGEventTap)
        InputBlocker.shared.checkAccessibilityPermission()

        BreakScheduler.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        BreakScheduler.shared.stop()
        InputBlocker.shared.disable()
    }
}
