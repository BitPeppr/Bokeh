import AppKit
import ServiceManagement // Added for SMAppService
import CoreGraphics // Added for screen capture permissions

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

        // Proactively request Screen Recording permission on startup
        requestScreenCapturePermission()

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
            // User clicked "Yes"
            toggleLoginItem(enable: true)
        }
        // Regardless of choice, mark that we've asked
        UserPreferences.shared.hasAskedForLoginItem = true
    }

    func isLoginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled { return true }
        }
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
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                    print("[EyeRest] Registered as login item (SMAppService).")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("[EyeRest] Unregistered as login item (SMAppService).")
                }
                NotificationCenter.default.post(name: .loginItemStatusChanged, object: nil)
                return
            } catch {
                print("[EyeRest] SMAppService error: \(error). Falling back to LaunchAgent.")
            }
        }

        let fm = FileManager.default
        let plistURL = launchAgentPlistURL()
        if enable {
            // build plist dict
            let bundlePath = Bundle.main.bundlePath
            let execName = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? ((bundlePath as NSString).lastPathComponent)
            let execPath = (bundlePath as NSString).appendingPathComponent("Contents/MacOS/\(execName)")
            let label = Bundle.main.bundleIdentifier ?? "com.yourname.EyeRest"
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "KeepAlive": true
            ]
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
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
                    NotificationCenter.default.post(name: .loginItemStatusChanged, object: nil)
                } else {
                    print("[EyeRest] LaunchAgent plist not present at \(plistURL.path)")
                }
            } catch {
                print("[EyeRest] Failed to remove LaunchAgent plist: \(error)")
            }
        }
    }

    private func revealAppInFinder() {
        DispatchQueue.main.async {
            let url = Bundle.main.bundleURL
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func requestScreenCapturePermission() {
        // Request access; the system may not automatically list the app in Settings.
        // If permission is denied, offer to open Settings and reveal the app in Finder
        // so the user can add it via the + button.
        if !CGRequestScreenCaptureAccess() {
            print("[EyeRest] Screen recording permission not granted. Blur overlay may not function correctly.")
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = """
            EyeRest needs 'Screen Recording' permission to display the blurred overlay.
            If EyeRest isn't listed in System Settings → Privacy & Security → Screen Recording, add it using the + button.

            Would you like me to open that Settings page and reveal the app in Finder now?
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings and Reveal App")
            alert.addButton(withTitle: "Reveal App in Finder")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
                revealAppInFinder()
            } else if response == .alertSecondButtonReturn {
                revealAppInFinder()
            }
        }
    }
}

