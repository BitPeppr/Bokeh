import AppKit

final class OverlayManager {
    static let shared = OverlayManager()
    private var controllers: [OverlayWindowController] = []

    init() {
        rebuildControllers()
    }

    func registerScreenObserver() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screensChanged() {
        rebuildControllers()
    }

    private func rebuildControllers() {
        controllers.removeAll()
        for screen in NSScreen.screens {
            controllers.append(OverlayWindowController(screen: screen))
        }
    }
}
