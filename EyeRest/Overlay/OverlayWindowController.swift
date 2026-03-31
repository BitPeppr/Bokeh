import AppKit
import SwiftUI
import Combine

final class OverlayNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayWindowController: NSObject {
    private let screen: NSScreen
    private var window: OverlayNSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(screen: NSScreen) {
        self.screen = screen
        super.init()
        setupWindow()
        observeScheduler()
    }

    private func setupWindow() {
        let win = OverlayNSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        // Level 101: above menu bar (24), Dock (20), and all ordinary app windows.
        win.level = .screenSaver

        // .canJoinAllSpaces → present in all virtual desktops AND full-screen Spaces
        // .stationary       → not moved by Exposé / Mission Control
        // .ignoresCycle     → excluded from CMD+Tab / CMD+` cycling
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = false

        // Use screen.frame (NOT screen.visibleFrame) — we want to cover the menu bar too.
        win.setFrame(screen.frame, display: false)

        // Create container - content will be added when overlay is shown
        let container = NSView(frame: screen.frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        win.contentView = container
        
        self.window = win
    }

    private func observeScheduler() {
        BreakScheduler.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .idle:
                    self?.hideOverlay()
                case .breakActive:
                    self?.showOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func showOverlay() {
        guard let window, let container = window.contentView else { return }
        
        // Clear any existing subviews
        container.subviews.forEach { $0.removeFromSuperview() }
        
        // Use simple semi-transparent overlay - no permissions needed, no flickering
        let overlayView = NSView(frame: screen.frame)
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        overlayView.autoresizingMask = [.width, .height]
        container.addSubview(overlayView)
        
        // Add SwiftUI content
        let contentView = OverlayView().environmentObject(BreakScheduler.shared)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = screen.frame
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        
        // Animate in
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            window.animator().alphaValue = 1.0
        }
    }

    private func hideOverlay() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak window] in
            window?.orderOut(nil)
            window?.alphaValue = 1.0  // reset for next show
        })
    }
}
