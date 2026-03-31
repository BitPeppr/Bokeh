import AppKit
import SwiftUI
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins

final class OverlayNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayWindowController: NSObject {
    private let screen: NSScreen
    private var window: OverlayNSWindow?
    private var cancellables = Set<AnyCancellable>()
    private let context = CIContext()

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

        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = false

        win.setFrame(screen.frame, display: false)

        // Important: Use bounds relative to window, not screen coordinates
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        win.contentView = container
        
        self.window = win
    }

    private func observeScheduler() {
        BreakScheduler.shared.$state
            .receive(on: DispatchQueue.main)
            .removeDuplicates { prev, current in
                // Only trigger show/hide when switching between idle and active.
                // Ignore changes to the countdown value within the active state.
                switch (prev, current) {
                case (.idle, .idle): return true
                case (.breakActive, .breakActive): return true
                default: return false
                }
            }
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
        
        let bounds = container.bounds
        
        // 1. Capture and Blur Screenshot
        if let blurredImage = createBlurredScreenshot() {
            let imageView = NSImageView(frame: bounds)
            imageView.image = blurredImage
            imageView.imageScaling = .scaleAxesIndependently
            imageView.autoresizingMask = [.width, .height]
            container.addSubview(imageView)
        } else {
            // Fallback to solid color if screenshot fails
            let fallbackView = NSView(frame: bounds)
            fallbackView.wantsLayer = true
            fallbackView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor // Slightly darker fallback
            fallbackView.autoresizingMask = [.width, .height]
            container.addSubview(fallbackView)
        }
        
        // 2. Add Dark Tint for contrast
        let tintView = NSView(frame: bounds)
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor // Lighter tint
        tintView.autoresizingMask = [.width, .height]
        container.addSubview(tintView)
        
        // 3. Add SwiftUI content
        let contentView = OverlayView().environmentObject(BreakScheduler.shared)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = bounds
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
            window?.alphaValue = 1.0
            // Clear subviews to free up memory (especially the blurred image)
            window?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        })
    }

    private func createBlurredScreenshot() -> NSImage? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        
        guard let imageRef = CGDisplayCreateImage(displayID) else {
            return nil
        }
        
        let ciImage = CIImage(cgImage: imageRef)
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = ciImage
        blurFilter.radius = 30.0
        
        // Crop to avoid transparent edges from blur
        _ = CIFilter.sourceOverCompositing() // Just a placeholder for cropping logic if needed
        let blurred = blurFilter.outputImage?.clampedToExtent().cropped(to: ciImage.extent)
        
        if let output = blurred, let cgImage = context.createCGImage(output, from: ciImage.extent) {
            return NSImage(cgImage: cgImage, size: screen.frame.size)
        }
        
        return nil
    }
}
