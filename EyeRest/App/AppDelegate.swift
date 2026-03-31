import AppKit
import ServiceManagement
import CoreGraphics
import ScreenCaptureKit

extension Notification.Name {
    static let loginItemStatusChanged = Notification.Name("EyeRest.loginItemStatusChanged")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders alongside LSUIElement in Info.plist
        NSApp.setActivationPolicy(.accessory)

        BreakScheduler.shared.registerSleepWakeObservers()
        OverlayManager.shared.registerScreenObserver()

        // Prompt for Accessibility permission (required for CGEventTap)
        InputBlocker.shared.checkAccessibilityPermission()

        // Trigger Screen Recording permission prompt on startup
        triggerScreenCapturePermission()

        BreakScheduler.shared.start()

        // Check for first run and prompt for login item
        if !UserPreferences.shared.hasAskedForLoginItem {
            promptForLoginItem()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        BreakScheduler.shared.stop()
        InputBlocker.shared.disable()
    }

    private func promptForLoginItem() {
        let alert = NSAlert()
        alert.messageText = "Launch EyeRest at Login?"
        alert.informativeText = "Do you want EyeRest to automatically start when you log in to your Mac? You can change this setting later in the menu bar."
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            toggleLoginItem(enable: true)
        }
        UserPreferences.shared.hasAskedForLoginItem = true
    }

    func isLoginItemEnabled() -> Bool {
        // For unsigned/ad-hoc apps, SMAppService won't work reliably.
        // Check LaunchAgent plist existence as the source of truth.
        let fm = FileManager.default
        let url = launchAgentPlistURL()
        return fm.fileExists(atPath: url.path)
    }

    private func launchAgentPlistURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.yourname.EyeRest"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(bundleID).plist")
    }

    func toggleLoginItem(enable: Bool) {
        // For unsigned apps, SMAppService.mainApp.register() fails silently.
        // Use LaunchAgent plist directly for reliable login-item behavior.
        let fm = FileManager.default
        let plistURL = launchAgentPlistURL()
        
        if enable {
            let bundlePath = Bundle.main.bundlePath
            let label = Bundle.main.bundleIdentifier ?? "com.yourname.EyeRest"
            // Use "open" command to launch the .app bundle properly
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-a", bundlePath],
                "RunAtLoad": true
            ]
            do {
                let launchAgentsDir = plistURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: launchAgentsDir.path) {
                    try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
                }
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: plistURL, options: .atomic)
                print("[EyeRest] Wrote LaunchAgent plist to \(plistURL.path)")
                NotificationCenter.default.post(name: .loginItemStatusChanged, object: nil)
            } catch {
                print("[EyeRest] Failed to write LaunchAgent plist: \(error)")
            }
        } else {
            do {
                if fm.fileExists(atPath: plistURL.path) {
                    try fm.removeItem(at: plistURL)
                    print("[EyeRest] Removed LaunchAgent plist at \(plistURL.path)")
                }
                NotificationCenter.default.post(name: .loginItemStatusChanged, object: nil)
            } catch {
                print("[EyeRest] Failed to remove LaunchAgent plist: \(error)")
            }
        }
    }

    private func triggerScreenCapturePermission() {
        // ScreenCaptureKit's SCShareableContent.getExcludingDesktopWindows triggers
        // the system permission prompt for Screen Recording on macOS 12.3+.
        // This is the modern way to request permission and shows the native toggle UI.
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            if let error = error {
                print("[EyeRest] Screen capture permission check: \(error.localizedDescription)")
            } else {
                print("[EyeRest] Screen capture permission granted or prompt shown.")
            }
        }
    }
}

