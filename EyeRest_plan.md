# EyeRest — Implementation Plan
### A macOS eye-break reminder with full-screen blur overlay

---

## 0. Table of Contents

1. [Project Overview](#1-project-overview)
2. [Technical Feasibility & Research Notes](#2-technical-feasibility--research-notes)
3. [Technology Stack Decisions](#3-technology-stack-decisions)
4. [Project Structure](#4-project-structure)
5. [Core Architecture](#5-core-architecture)
6. [Module Deep-Dives](#6-module-deep-dives)
   - 6.1 AppDelegate / App Entry
   - 6.2 BreakScheduler
   - 6.3 OverlayWindowController
   - 6.4 OverlayView (SwiftUI)
   - 6.5 BlurView (NSVisualEffectView wrapper)
   - 6.6 OverlayManager (Multi-Monitor)
   - 6.7 InputBlocker (CGEventTap)
   - 6.8 MenuBarController
   - 6.9 UserPreferences
7. [Window Level & Space Behaviour Strategy](#7-window-level--space-behaviour-strategy)
8. [Blur Strategy](#8-blur-strategy)
9. [Multi-Monitor Strategy](#9-multi-monitor-strategy)
10. [Input Blocking Strategy](#10-input-blocking-strategy)
11. [Entitlements, Permissions & Code Signing](#11-entitlements-permissions--code-signing)
12. [Info.plist Keys](#12-infoplist-keys)
13. [Build & Run Instructions](#13-build--run-instructions)
14. [Edge Cases & Hardening](#14-edge-cases--hardening)
15. [Future / Optional Enhancements](#15-future--optional-enhancements)
16. [File-by-File Implementation Checklist](#16-file-by-file-implementation-checklist)

---

## 1. Project Overview

**Goal:** A lightweight, always-running macOS menu bar agent that, every 20 minutes, covers all screens with a blurred overlay and a countdown from 30 seconds, reminding the user to rest their eyes (the 20-20-20 rule: look 20 feet away for 20 seconds). The break cannot be bypassed via keyboard shortcuts. The overlay must:

- Cover **all connected displays** simultaneously
- Appear **above every other window**, including full-screen apps in their own Spaces
- Show a **blur** of the desktop content beneath it (not a solid color)
- Display a **message** + **live countdown**
- Dismiss automatically after 30 seconds
- **Block keyboard shortcuts** (Cmd+Q, Cmd+Tab, Cmd+Space, etc.) during the break
- Provide an **emergency escape hatch** via a deliberate hidden chord
- **Not appear in the Dock** or CMD+Tab switcher (background agent)
- Run persistently, launched manually or at login

**Constraints / Allowances:**
- SIP disabled is acceptable (makes CGEventTap more robust; not required for the overlay itself)
- No App Store distribution — self-signed or ad-hoc signature is fine
- No Hardened Runtime required (simplifies entitlements)
- macOS 13 Ventura+ as minimum target (allows modern SwiftUI APIs)
- Built with Swift + AppKit/SwiftUI hybrid (not a command-line-only tool)

---

## 2. Technical Feasibility & Research Notes

### 2.1 Full-Screen Overlay Above All Spaces

This is the core technical challenge. By default, an `NSWindow` is pinned to the Space it was created in. When a user switches to a full-screen app (which creates a dedicated Mission Control Space), ordinary overlay windows stay behind.

**Solution confirmed:**

```swift
window.level = NSWindow.Level.screenSaver  // raw value 101
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
```

- `.screenSaver` level (101) is above the Dock (20), menu bar (24), status bar (25), and pop-up menus. It is the level used by the macOS screensaver — exactly the visual analogue of what we want.
- `.canJoinAllSpaces` makes the window follow all virtual desktops and full-screen app Spaces.
- `.stationary` prevents Exposé/Mission Control from moving the window.
- `.ignoresCycle` removes it from CMD+Tab / CMD+` window cycling.

> **Important:** Do NOT include `.fullScreenAuxiliary` in `collectionBehavior`. That flag opts a window into *joining* an existing full-screen Space in split-view mode — the opposite of what we want. Our window should float above all Spaces, not participate in one.

This does **not** require SIP to be disabled — the window level combination is a fully supported AppKit API.

### 2.2 Blur Effect

`NSVisualEffectView` with `blendingMode = .behindWindow` and `state = .active` provides a live compositor blur of all window content behind our overlay. Because the overlay is at `.screenSaver` level, everything else is below it in the compositor, so the blur captures apps, the desktop, and full-screen app Spaces.

**Important:** `NSVisualEffectView` with `.behindWindow` is a **compositor-level** blur applied by WindowServer. It does not capture screen pixels in your process, so it does not require Screen Recording permission.

### 2.3 Multi-Monitor

One `NSWindow` only covers one `NSScreen`. For multi-monitor setups, one `OverlayWindowController` must be created per screen, each sized to `screen.frame`. A `NSApplication.didChangeScreenParametersNotification` observer handles displays being connected/disconnected at runtime.

### 2.4 Input Blocking with CGEventTap

To prevent the user from bypassing the overlay via keyboard shortcuts, a `CGEventTap` intercepts and discards events at the system level during the break.

**Requirements:**
- The app must be granted **Accessibility permission** in System Settings → Privacy & Security → Accessibility.
- With SIP disabled, the tap can be placed at `.cghidEventTap` for raw HID-level interception. Without SIP disabled, `.cgAnnotatedSessionEventTap` is sufficient.
- The tap is enabled only for the 30-second break duration.

An **emergency escape hatch** — `Ctrl+Opt+Cmd+Shift+E` — bypasses the tap in genuine emergencies. The chord is documented in the menu bar UI.

### 2.5 Menu Bar Agent

`LSUIElement = YES` in `Info.plist` suppresses the Dock icon and hides the app from CMD+Tab. Combined with SwiftUI `MenuBarExtra`, this gives a persistent tray icon.

### 2.6 Timer Architecture

`DispatchSourceTimer` (preferred over `Foundation.Timer`) is used for the 20-minute interval — it is more accurate for long-running timers in background processes and immune to runloop starvation. A `Foundation.Timer` drives the 1-second countdown on the main runloop. Both are paused on sleep and reset on wake.

---

## 3. Technology Stack Decisions

| Concern | Choice | Rationale |
|---|---|---|
| Language | Swift 5.9+ | Native, type-safe, excellent AppKit interop |
| UI framework | SwiftUI + AppKit hybrid | SwiftUI for overlay content; AppKit (`NSWindow`) for window-level control |
| Blur | `NSVisualEffectView` (AppKit) | Only reliable way to get a live compositor blur on macOS |
| Window management | `NSWindow` subclass | Full control over `level`, `collectionBehavior`, `styleMask` |
| Timer (interval) | `DispatchSourceTimer` | More accurate than `Foundation.Timer` for long-running background timers |
| Timer (countdown) | `Foundation.Timer` on main thread | Directly drives UI updates at 1s granularity |
| Input blocking | `CGEventTap` | System-level event interception; requires Accessibility permission |
| Menu bar | SwiftUI `MenuBarExtra` | Modern API (macOS 13+), cleaner than manual `NSStatusItem` |
| Preferences | `UserDefaults` / `@AppStorage` | Simple key-value persistence |
| Build system | Xcode project | Required for Swift compilation and `.app` bundle creation |
| Code signing | Ad-hoc (`codesign -s -`) | Sufficient for local use; no Apple Developer account needed |

---

## 4. Project Structure

```
EyeRest/
├── EyeRest.xcodeproj/
│
├── EyeRest/                              # Main target sources
│   ├── App/
│   │   ├── EyeRestApp.swift              # @main App entry, MenuBarExtra scene
│   │   └── AppDelegate.swift             # NSApplicationDelegate for lifecycle hooks
│   │
│   ├── Scheduling/
│   │   └── BreakScheduler.swift          # All timer logic, sleep/wake handling
│   │
│   ├── Overlay/
│   │   ├── OverlayManager.swift          # Per-screen controller management
│   │   ├── OverlayWindowController.swift # NSWindow subclass + controller per screen
│   │   ├── OverlayView.swift             # SwiftUI view: message + countdown
│   │   └── BlurView.swift                # NSViewRepresentable for NSVisualEffectView
│   │
│   ├── Input/
│   │   └── InputBlocker.swift            # CGEventTap setup and management
│   │
│   ├── MenuBar/
│   │   └── MenuBarView.swift             # SwiftUI popover content for tray icon
│   │
│   ├── Preferences/
│   │   └── UserPreferences.swift         # @AppStorage / UserDefaults wrapper
│   │
│   └── Resources/
│       ├── Info.plist                    # LSUIElement, NSPrincipalClass, etc.
│       ├── EyeRest.entitlements          # Minimal entitlements (no sandbox)
│       └── Assets.xcassets/
│           └── AppIcon.appiconset/       # Menu bar icon (16pt, 32pt @2x)
│
└── README.md
```

---

## 5. Core Architecture

### State machine

```
IDLE ──(timer fires)──► BREAK ──(countdown = 0 OR emergency escape)──► IDLE
  ▲                                                                        │
  └────────────────────────────(loop)──────────────────────────────────────┘
```

`BreakScheduler` is the single source of truth and owns all timer logic. `OverlayWindowController` instances and `InputBlocker` observe `BreakScheduler.$state` and react to transitions.

### Data flow

```
BreakScheduler (ObservableObject)
    │
    ├── @Published state: .idle | .breakActive(secondsRemaining: Int)
    │
    ├── OverlayManager
    │   └── OverlayWindowController × N (one per NSScreen)
    │           └── NSHostingView<OverlayView>
    │                   ├── BlurView (NSVisualEffectView — compositor blur)
    │                   ├── Dark tint overlay
    │                   ├── Message text + eye icon
    │                   └── Countdown ring + number
    │
    ├── InputBlocker
    │   └── CGEventTap (enabled during .breakActive, disabled during .idle)
    │
    └── MenuBarView (SwiftUI)
            ├── "Next break in X:XX"
            ├── "Take break now" button
            ├── Skip / pause toggles
            ├── Interval picker
            └── Emergency chord reminder
```

---

## 6. Module Deep-Dives

### 6.1 AppDelegate / App Entry

```swift
// EyeRestApp.swift
@main
struct EyeRestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var scheduler = BreakScheduler.shared

    var body: some Scene {
        MenuBarExtra("EyeRest", systemImage: "eye") {
            MenuBarView()
                .environmentObject(scheduler)
        }
        .menuBarExtraStyle(.window)
    }
}
```

```swift
// AppDelegate.swift
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
```

---

### 6.2 BreakScheduler (`Scheduling/BreakScheduler.swift`)

```swift
enum AppState: Equatable {
    case idle
    case breakActive(secondsRemaining: Int)
}

final class BreakScheduler: ObservableObject {
    static let shared = BreakScheduler()

    @Published private(set) var state: AppState = .idle
    @Published private(set) var nextBreakIn: TimeInterval = 0

    var breakInterval: TimeInterval { UserPreferences.shared.breakInterval }
    var countdownDuration: Int { UserPreferences.shared.countdownDuration }

    // DispatchSourceTimer for the 20-minute interval
    private var breakDispatchTimer: DispatchSourceTimer?
    // Foundation.Timer for the 1-second countdown (main thread UI updates)
    private var countdownTimer: Timer?
    private var nextBreakDate: Date?

    // MARK: - Public API

    func start() { scheduleNextBreak() }
    func stop() { cancelAll() }
    func triggerBreakNow() { beginBreak() }
    func resetSchedule() { scheduleNextBreak() }   // called when interval pref changes
    func endBreakEarly() { endBreak() }             // called by emergency escape or skip

    // MARK: - Private

    private func scheduleNextBreak() {
        cancelAll()
        nextBreakDate = Date().addingTimeInterval(breakInterval)

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + breakInterval, repeating: .never)
        timer.setEventHandler { [weak self] in self?.beginBreak() }
        timer.resume()
        breakDispatchTimer = timer

        scheduleTick()
    }

    private func beginBreak() {
        cancelDispatchTimer()
        var remaining = countdownDuration
        state = .breakActive(secondsRemaining: remaining)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            remaining -= 1
            if remaining <= 0 { self.endBreak() }
            else { self.state = .breakActive(secondsRemaining: remaining) }
        }
    }

    private func endBreak() {
        cancelCountdownTimer()
        state = .idle
        scheduleNextBreak()
    }

    private func cancelDispatchTimer() { breakDispatchTimer?.cancel(); breakDispatchTimer = nil }
    private func cancelCountdownTimer() { countdownTimer?.invalidate(); countdownTimer = nil }
    private func cancelAll() {
        cancelDispatchTimer()
        cancelCountdownTimer()
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - Sleep / Wake

    func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(systemWillSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(systemDidWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func systemWillSleep() {
        // Sleep counts as rest — cancel any active break and all timers.
        cancelAll()
        state = .idle
    }

    @objc private func systemDidWake() {
        // Always reset the full interval on wake — never surprise the user right after wake.
        scheduleNextBreak()
    }

    // MARK: - Tick (for menu bar "next break in X:XX")

    private var tickTimer: Timer?
    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let date = self.nextBreakDate else { return }
            self.nextBreakIn = max(0, date.timeIntervalSinceNow)
        }
    }
}
```

**Key design decisions:**
- `DispatchSourceTimer` for the 20-minute interval: more reliable than `Foundation.Timer` in long-running background agents.
- `Foundation.Timer` on the main runloop for the countdown: safe to mutate `@Published` state without `DispatchQueue.main.async`.
- Sleep/wake: cancel everything on sleep, fresh full interval on wake. If a break was active, sleep constitutes the rest.

---

### 6.3 OverlayWindowController (`Overlay/OverlayWindowController.swift`)

One instance per `NSScreen`. Owns the `NSWindow` and manages show/hide animations.

```swift
// Subclass required: borderless NSWindow returns false for canBecomeKey by default,
// preventing the skip button from receiving click events via the responder chain.
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

        // ── CRITICAL WINDOW CONFIGURATION ──────────────────────────────────────

        // Level 101: above menu bar (24), Dock (20), and all ordinary app windows.
        win.level = .screenSaver

        // .canJoinAllSpaces → present in all virtual desktops AND full-screen Spaces
        // .stationary       → not moved by Exposé / Mission Control
        // .ignoresCycle     → excluded from CMD+Tab / CMD+` cycling
        // NOTE: Do NOT add .fullScreenAuxiliary — that is a split-view tiling flag,
        // not a "float above everything" flag.
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = false

        // Use screen.frame (NOT screen.visibleFrame) — we want to cover the menu bar too.
        win.setFrame(screen.frame, display: false)

        let overlayView = OverlayView().environmentObject(BreakScheduler.shared)
        win.contentView = NSHostingView(rootView: overlayView)
        self.window = win
    }

    private func observeScheduler() {
        BreakScheduler.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .idle:        self?.hideOverlay()
                case .breakActive: self?.showOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func showOverlay() {
        guard let window else { return }
        window.alphaValue = 0
        // orderFrontRegardless: shows window without requiring the app to be active.
        // Never use makeKeyAndOrderFront here — that would steal focus from the user's work.
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
```

---

### 6.4 OverlayView (`Overlay/OverlayView.swift`)

```swift
struct OverlayView: View {
    @EnvironmentObject var scheduler: BreakScheduler

    var body: some View {
        ZStack {
            // Layer 1: Compositor blur
            BlurView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // Layer 2: Dark tint for contrast
            Color.black.opacity(0.25).ignoresSafeArea()

            // Layer 3: Content
            VStack(spacing: 32) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.white.opacity(0.9))

                VStack(spacing: 8) {
                    Text("Rest Your Eyes")
                        .font(.system(size: 42, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Look at something 20 feet away")
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

                CountdownRing(scheduler: scheduler)

                // Skip button — optional, appears only after a 5-second delay
                if UserPreferences.shared.skipEnabled {
                    if case .breakActive(let remaining) = scheduler.state, remaining < 25 {
                        Button("Skip") { scheduler.endBreakEarly() }
                            .buttonStyle(SkipButtonStyle())
                            .transition(.opacity.animation(.easeIn(duration: 0.3)))
                    }
                }
            }
        }
    }
}

struct CountdownRing: View {
    @ObservedObject var scheduler: BreakScheduler
    private var total: Int { UserPreferences.shared.countdownDuration }

    private var remaining: Int {
        if case .breakActive(let r) = scheduler.state { return r }
        return total
    }
    private var progress: Double { Double(remaining) / Double(total) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 5)
                .frame(width: 100, height: 100)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.0), value: progress)
            Text("\(remaining)")
                .font(.system(size: 36, weight: .thin, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

struct SkipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(
                Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .background(Capsule().fill(Color.white.opacity(
                        configuration.isPressed ? 0.1 : 0.05)))
            )
    }
}
```

---

### 6.5 BlurView (`Overlay/BlurView.swift`)

```swift
struct BlurView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // .active: forces blur even when the window is not key.
        // CRITICAL — without this, the blur does not render because we use
        // orderFrontRegardless() and the window is never made key.
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
```

**Material options (darkest to lightest):**

| Material | Appearance |
|---|---|
| `.fullScreenUI` | Very dark, immersive |
| `.hudWindow` | Dark frosted glass — **recommended** |
| `.popover` | Medium frosted glass |
| `.sidebar` | Light frosted glass |

---

### 6.6 OverlayManager (`Overlay/OverlayManager.swift`)

```swift
final class OverlayManager {
    static let shared = OverlayManager()
    private var controllers: [OverlayWindowController] = []

    init() { rebuildControllers() }

    func registerScreenObserver() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screensChanged() {
        // New controllers observe BreakScheduler.$state immediately —
        // if a break is active, they will show their overlays right away.
        rebuildControllers()
    }

    private func rebuildControllers() {
        controllers.removeAll()
        for screen in NSScreen.screens {
            controllers.append(OverlayWindowController(screen: screen))
        }
    }
}
```

---

### 6.7 InputBlocker (`Input/InputBlocker.swift`)

This module intercepts and discards system input events during a break, preventing keyboard shortcut bypasses.

```swift
import Cocoa
import Combine

final class InputBlocker {
    static let shared = InputBlocker()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()

    init() { observeScheduler() }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        if !AXIsProcessTrustedWithOptions(options) {
            print("[EyeRest] Accessibility not granted — input blocking unavailable.")
        }
    }

    // MARK: - State Observation

    private func observeScheduler() {
        BreakScheduler.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .breakActive: self?.enable()
                case .idle:        self?.disable()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Enable / Disable

    func enable() {
        guard AXIsProcessTrusted() else { return }
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)          |
            (1 << CGEventType.keyUp.rawValue)            |
            (1 << CGEventType.flagsChanged.rawValue)     |
            (1 << CGEventType.scrollWheel.rawValue)      |
            (1 << CGEventType.leftMouseDown.rawValue)    |
            (1 << CGEventType.rightMouseDown.rawValue)   |
            (1 << CGEventType.otherMouseDown.rawValue)   |
            (1 << CGEventType.systemDefined.rawValue)

        // .cgAnnotatedSessionEventTap works without SIP disabled.
        // With SIP disabled, .cghidEventTap provides lower-level interception.
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,   // run before all other taps, including system
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eyeRestEventCallback,
            userInfo: nil
        ) else {
            print("[EyeRest] CGEvent.tapCreate failed — is Accessibility permission granted?")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
    }

    func disable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }
}

// MARK: - CGEventTap Callback (must be a C function — not a closure or method)

// Emergency escape: Ctrl + Option + Cmd + Shift + E  (keycode 14)
// Four modifiers + a letter makes accidental activation effectively impossible.
private let kEmergencyModifiers: CGEventFlags = [.maskControl, .maskAlternate,
                                                  .maskCommand, .maskShift]
private let kEmergencyKeyCode: CGKeyCode = 14  // 'E'

private func eyeRestEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Pass through system/null events that are not user-input types
    let blockedTypes: Set<CGEventType> = [.keyDown, .keyUp, .flagsChanged,
                                          .scrollWheel, .leftMouseDown,
                                          .rightMouseDown, .otherMouseDown, .systemDefined]
    guard blockedTypes.contains(type) else {
        return Unmanaged.passRetained(event)
    }

    // Check for emergency escape chord on keyDown
    if type == .keyDown {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags   = event.flags.intersection([.maskControl, .maskAlternate,
                                                .maskCommand, .maskShift])
        if keyCode == kEmergencyKeyCode && flags == kEmergencyModifiers {
            DispatchQueue.main.async { BreakScheduler.shared.endBreakEarly() }
            return Unmanaged.passRetained(event)
        }
    }

    // Discard all other events during the break
    return nil
}
```

**What the InputBlocker blocks:**

| Input | Blocked? |
|---|---|
| Cmd+Q | ✅ |
| Cmd+Tab / Cmd+` | ✅ |
| Cmd+Space (Spotlight) | ✅ |
| Cmd+Option+Esc (Force Quit) | ✅ |
| Mouse clicks (passing to apps below) | ✅ |
| Ctrl+Opt+Cmd+Shift+E | ❌ Emergency escape |

**Important implementation notes:**

- The callback is a **file-scope C function** — `CGEvent.tapCreate` requires a C function pointer. It cannot be a Swift closure or instance method.
- `.headInsertEventTap` runs the callback before all other event taps, including system-level ones (e.g. Cmd+Space).
- Returning `nil` destroys the event — it never reaches the window server or any application.
- The tap is **only active during breaks**. At all other times it does not exist and has zero performance impact.
- If the system disables the tap (timeout, crash), re-enable it in the tap-disabled callback path or via a watchdog timer.

---

### 6.8 MenuBarView (`MenuBar/MenuBarView.swift`)

```swift
struct MenuBarView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @ObservedObject var prefs = UserPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Image(systemName: "eye.circle.fill").foregroundStyle(.blue)
                switch scheduler.state {
                case .idle:
                    Text("Next break in \(formattedNextBreak)").font(.system(size: 13))
                case .breakActive(let r):
                    Text("Break active — \(r)s remaining")
                        .font(.system(size: 13)).foregroundStyle(.orange)
                }
            }

            Divider()

            Button("Take break now") { scheduler.triggerBreakNow() }
            Toggle("Allow skip button", isOn: $prefs.skipEnabled)
            Toggle("Pause schedule",    isOn: $prefs.paused)

            Divider()

            HStack {
                Text("Interval:").foregroundStyle(.secondary)
                Picker("", selection: $prefs.breakIntervalMinutes) {
                    Text("10 min").tag(10)
                    Text("20 min").tag(20)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }
                .pickerStyle(.menu).frame(width: 90)
            }

            Divider()

            // Emergency chord — inform the user it exists
            Text("Emergency exit during break:\n⌃⌥⌘⇧E")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Divider()

            Button("Quit EyeRest") { NSApplication.shared.terminate(nil) }
                .foregroundStyle(.red)
        }
        .padding(12)
        .frame(width: 260)
    }

    private var formattedNextBreak: String {
        let mins = Int(scheduler.nextBreakIn / 60)
        let secs = Int(scheduler.nextBreakIn) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

---

### 6.9 UserPreferences (`Preferences/UserPreferences.swift`)

```swift
final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    @AppStorage("breakIntervalMinutes") var breakIntervalMinutes: Int = 20 {
        didSet { BreakScheduler.shared.resetSchedule() }
    }
    @AppStorage("countdownDuration") var countdownDuration: Int = 30
    @AppStorage("skipEnabled")       var skipEnabled: Bool = false
    @AppStorage("paused") var paused: Bool = false {
        didSet {
            if paused { BreakScheduler.shared.stop() }
            else       { BreakScheduler.shared.start() }
        }
    }

    var breakInterval: TimeInterval { TimeInterval(breakIntervalMinutes * 60) }
}
```

---

## 7. Window Level & Space Behaviour Strategy

### CGWindowLevel hierarchy (ascending)

```
.normal          (0)
.floating        (3)
.modalPanel      (8)
.dock           (20)
.mainMenu       (24)
.statusBar      (25)
.popUpMenu /
.screenSaver   (101)  ← EyeRest lives here
.overlayWindow (102)
kCGMaximumWindowLevelKey (2147483631)
```

### Why `.screenSaver`

- Above the menu bar (24) and Dock (20): the overlay covers them completely
- No ordinary app window can appear above it
- The level the macOS screensaver uses — semantically correct for our use case
- Does not require SIP to be disabled

### Alternative: `.shieldingWindow`

```swift
let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.shieldingWindow)))
```

The shielding window level is used by the login screen and fast-user-switching overlay. It is higher than `.screenSaver`. For our use case `.screenSaver` is sufficient; use `.shieldingWindow` only if a specific system UI appears above our overlay.

### Why NOT `.fullScreenAuxiliary` in `collectionBehavior`

`.fullScreenAuxiliary` is a **split-view tiling** flag: it lets a window share an existing full-screen Space alongside a full-screen app. It does not float a window above all Spaces. Using it instead of `.canJoinAllSpaces` is a common mistake that results in the overlay only appearing in the current Space.

---

## 8. Blur Strategy

### Mechanism

`NSVisualEffectView` delegates blurring to WindowServer. It is a GPU-accelerated compositor-level effect that samples from layers below our window in the scene graph. It does **not** capture screen pixels in our process, so Screen Recording permission is not needed.

### Critical settings

```swift
view.blendingMode = .behindWindow  // blur content below this window in the compositor
view.state        = .active        // CRITICAL: always render blur even when not key window
```

The default `.followsWindowActiveState` renders only when the window is key. Since we use `orderFrontRegardless()`, the window is never the key window. Without `.active`, the view renders as a flat opaque color instead of a blur.

### Enhancing with a tint

Layer `Color.black.opacity(0.20–0.35)` on top of `BlurView` in SwiftUI for better text contrast without losing the blur transparency.

---

## 9. Multi-Monitor Strategy

One `NSWindow` per `NSScreen`. Each window's frame is set to `screen.frame` (the full physical display rectangle, including menu bar area). Creating windows in this way places the overlay precisely on each physical display regardless of their arrangement in System Settings → Displays.

If a display is added or removed at runtime, `NSApplication.didChangeScreenParametersNotification` fires. `OverlayManager.rebuildControllers()` tears down all existing controllers and creates new ones. Because `BreakScheduler.state` is still `.breakActive` during an active break, the new controllers observe the state and immediately show their overlays.

---

## 10. Input Blocking Strategy

### Tap point options

| Tap point | Notes |
|---|---|
| `.cghidEventTap` | Raw HID events before system processing. Best coverage. Requires SIP disabled on modern macOS. |
| `.cgAnnotatedSessionEventTap` | After HID annotation. Works without SIP disabled. Sufficient for our needs. |
| `.cgSessionEventTap` | Slightly earlier than annotated. Similar to the above. |

Use `.cgAnnotatedSessionEventTap` as the default. With SIP disabled (permitted in this project), `.cghidEventTap` is also viable.

### Accessibility permission flow

On first launch, `checkAccessibilityPermission()` calls `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true`. This shows the system dialog directing the user to System Settings → Privacy & Security → Accessibility. The user adds EyeRest and toggles it on.

If permission is not granted, the overlay still displays and the countdown still runs — only keyboard blocking is unavailable. Log a console warning.

### Emergency escape hatch

`Ctrl+Opt+Cmd+Shift+E` is:
- Four modifier keys + one letter — effectively impossible to hit accidentally
- Documented in the menu bar popover
- Documented in the README
- Calls `BreakScheduler.shared.endBreakEarly()`, which ends the break, disables the event tap, and restarts the 20-minute interval from scratch

---

## 11. Entitlements, Permissions & Code Signing

### Required permissions

| Capability | Required? | Notes |
|---|---|---|
| App Sandbox | **No — must be disabled** | Sandbox interferes with window level promotion and CGEventTap |
| Accessibility | **Yes** (for input blocking) | User grants in System Settings |
| Screen Recording | **No** | NSVisualEffectView does not capture pixels |
| Hardened Runtime | **No** | Personal tool |

### Entitlements file

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

### Code signing (ad-hoc)

```bash
codesign --force --deep --sign - /path/to/EyeRest.app
codesign -dv --verbose=4 /path/to/EyeRest.app   # verify
```

### Gatekeeper bypass

```bash
# Remove quarantine attribute (cleanest approach with SIP disabled)
xattr -cr /path/to/EyeRest.app
```

---

## 12. Info.plist Keys

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>    <string>com.yourname.EyeRest</string>
    <key>CFBundleName</key>          <string>EyeRest</string>
    <key>CFBundleVersion</key>       <string>1</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleExecutable</key>    <string>EyeRest</string>
    <key>CFBundlePackageType</key>   <string>APPL</string>

    <!-- Hides Dock icon and removes from CMD+Tab -->
    <key>LSUIElement</key>           <true/>

    <key>LSMinimumSystemVersion</key> <string>13.0</string>
    <key>NSPrincipalClass</key>      <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsSuddenTermination</key> <false/>

    <!-- Human-readable reason shown in Privacy & Security Accessibility prompt -->
    <key>NSAccessibilityUsageDescription</key>
    <string>EyeRest uses Accessibility to block keyboard shortcuts during eye-rest breaks, ensuring the break is not accidentally dismissed.</string>
</dict>
</plist>
```

---

## 13. Build & Run Instructions

### Prerequisites

- Xcode 15+ (Swift 5.9, macOS 13 SDK)
- macOS 13 Ventura or later
- SIP disabled recommended (run `csrutil status` to verify) — not required for the overlay itself, improves `CGEventTap` coverage

### Xcode project setup

1. File → New → Project → macOS → App
2. Interface: SwiftUI, Lifecycle: SwiftUI App
3. Bundle ID: `com.yourname.EyeRest`
4. **Signing & Capabilities:** Uncheck "Enable App Sandbox" — most common setup mistake
5. Add `LSUIElement = YES` and `NSAccessibilityUsageDescription` to Info.plist
6. Replace generated files with the structure in §4

### Key build settings

| Setting | Value |
|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | `13.0` |
| `CODE_SIGN_STYLE` | `Manual` |
| `CODE_SIGN_IDENTITY` | `-` (ad-hoc) |
| `ENABLE_HARDENED_RUNTIME` | `NO` |
| `ENABLE_APP_SANDBOX` | `NO` |

### First-run setup

1. Launch EyeRest — the system prompts for Accessibility permission
2. System Settings → Privacy & Security → Accessibility → enable EyeRest
3. Menu bar icon appears; schedule begins
4. Test via "Take break now" in the menu bar

### Launch at login

```swift
import ServiceManagement
try? SMAppService.mainApp.register()    // enable
try? SMAppService.mainApp.unregister()  // disable
var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
```

### launchd keepalive (crash resilience)

```xml
<!-- ~/Library/LaunchAgents/com.yourname.eyerest.plist -->
<plist version="1.0">
<dict>
    <key>Label</key>             <string>com.yourname.eyerest</string>
    <key>ProgramArguments</key>
    <array><string>/Applications/EyeRest.app/Contents/MacOS/EyeRest</string></array>
    <key>RunAtLoad</key>         <true/>
    <key>KeepAlive</key>         <true/>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.yourname.eyerest.plist
```

---

## 14. Edge Cases & Hardening

### 14.1 System sleep / wake

Cancel all timers on `willSleepNotification`. Reset the full interval on `didWakeNotification`. Sleep counts as rest — if a break was active, the sleep/wake cycle replaces it. Never resume a timer that was active before sleep.

### 14.2 Screen lock / screensaver

The macOS screensaver also runs at `.screenSaver` level and covers our window when activated. This is acceptable — the screensaver is a rest event. Listen via `DistributedNotificationCenter`:

```swift
// On "com.apple.screensaver.started": endBreakEarly() — screensaver IS the rest
// On "com.apple.screensaver.stopped": resetSchedule() — fresh full interval
DistributedNotificationCenter.default().addObserver(
    self, selector: #selector(screensaverStarted),
    name: NSNotification.Name("com.apple.screensaver.started"), object: nil)
DistributedNotificationCenter.default().addObserver(
    self, selector: #selector(screensaverStopped),
    name: NSNotification.Name("com.apple.screensaver.stopped"), object: nil)
```

### 14.3 CGEventTap auto-disable

The system can disable a `CGEventTap` if the callback is unresponsive or the process loses Accessibility permission. Detect this via the tap type `.tapDisabledByUserInput` / `.tapDisabledByTimeout` in the callback, or with a watchdog timer during breaks:

```swift
// In a watchdog timer (fires every 5s during a break):
if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
    CGEvent.tapEnable(tap: tap, enable: true)
}
```

### 14.4 Accessibility permission revoked at runtime

If revoked while running, the event tap becomes invalid. The tap-disabled callback path catches this. Disable the tap cleanly; the overlay continues to display, only input blocking is lost.

### 14.5 Display hot-plug during break

`screensChanged()` → `rebuildControllers()` → new controllers observe `.breakActive` → immediately show overlays on the new screen configuration.

### 14.6 App crash

The launchd `KeepAlive` plist restarts EyeRest. On relaunch, the scheduler starts fresh with a full 20-minute interval.

### 14.7 Fast user switching

Overlay windows are per-session by macOS architecture. No special handling needed.

### 14.8 Screenshots

By default, `.screenSaver` level windows appear in CMD+Shift+3 screenshots. Intentional — the break is real. To exclude from screen capture if desired:

```swift
win.sharingType = .none
```

---

## 15. Future / Optional Enhancements

| Feature | Notes |
|---|---|
| Sound chime | `NSSound(named: .init("Glass"))?.play()` on break start/end |
| Idle detection | Track last input timestamp in `InputBlocker`. If idle > 20 min, skip the break. |
| Custom message | `UserPreferences.shared.breakMessage: String` passed into `OverlayView` |
| Break statistics | Local SQLite via GRDB — completed vs skipped breaks, weekly compliance |
| Focus mode integration | Check system DND state; skip break if active |
| Gradual fade-in | Increase `NSAnimationContext` duration to 2–3 seconds |
| Animated background | SwiftUI `TimelineView` + `Canvas` particle effect |
| Notch-aware layout | `NSScreen.safeAreaInsets` on MacBook Pro notch models |
| Pomodoro mode | Alternate 25-min work / 5-min break / 15-min long break |
| Per-app exclusion | Monitor `NSWorkspace.shared.frontmostApplication`; skip if in exclusion list |

---

## 16. File-by-File Implementation Checklist

Implement in this order — each file depends only on those above it.

```
[1]  EyeRest/Resources/Info.plist
     → LSUIElement = YES, NSAccessibilityUsageDescription, bundle IDs.
     → No code dependencies.

[2]  EyeRest/Resources/EyeRest.entitlements
     → com.apple.security.app-sandbox = false. Nothing else.
     → No code dependencies.

[3]  EyeRest/Preferences/UserPreferences.swift
     → @AppStorage wrappers for all user-configurable values.
     → No dependencies.

[4]  EyeRest/Scheduling/BreakScheduler.swift
     → DispatchSourceTimer for 20-min interval.
     → Foundation.Timer for 1-second countdown.
     → Sleep/wake + screensaver observers.
     → Depends on: UserPreferences.

[5]  EyeRest/Input/InputBlocker.swift
     → CGEventTap setup, enable/disable.
     → eyeRestEventCallback C function with emergency escape chord.
     → Observes BreakScheduler.$state.
     → Depends on: BreakScheduler.

[6]  EyeRest/Overlay/BlurView.swift
     → NSViewRepresentable wrapping NSVisualEffectView.
     → state = .active, blendingMode = .behindWindow.
     → No dependencies.

[7]  EyeRest/Overlay/OverlayView.swift
     → ZStack: BlurView + tint + eye icon + message + CountdownRing + skip button.
     → Depends on: BlurView, BreakScheduler, UserPreferences.

[8]  EyeRest/Overlay/OverlayWindowController.swift
     → OverlayNSWindow subclass (canBecomeKey = true, canBecomeMain = false).
     → Window level, collectionBehavior, frame.
     → NSHostingView<OverlayView>.
     → orderFrontRegardless() + NSAnimationContext fade in/out.
     → Depends on: OverlayView, BreakScheduler.

[9]  EyeRest/Overlay/OverlayManager.swift
     → [OverlayWindowController] array, one per NSScreen.screens entry.
     → NSApplication.didChangeScreenParametersNotification observer.
     → Depends on: OverlayWindowController.

[10] EyeRest/MenuBar/MenuBarView.swift
     → Status, take-break-now, skip toggle, pause toggle, interval picker,
       emergency chord reminder, quit.
     → Depends on: BreakScheduler, UserPreferences.

[11] EyeRest/App/AppDelegate.swift
     → NSApp.setActivationPolicy(.accessory).
     → Register observers: sleep/wake, screen change, screensaver.
     → InputBlocker.shared.checkAccessibilityPermission().
     → BreakScheduler.shared.start().
     → Depends on: BreakScheduler, OverlayManager, InputBlocker.

[12] EyeRest/App/EyeRestApp.swift
     → @main entry, @NSApplicationDelegateAdaptor.
     → MenuBarExtra scene with MenuBarView.
     → Depends on: AppDelegate, MenuBarView, BreakScheduler.

[13] EyeRest/Resources/Assets.xcassets
     → AppIcon.appiconset (any icon).
     → Template menu bar icon (16×16 @1x, 32×32 @2x).
     → SF Symbol "eye" works as a placeholder.
```

### Critical implementation warnings for the implementing model

1. **Disable App Sandbox** in Xcode Signing & Capabilities. This is the most common mistake. A sandboxed app cannot promote its window to `.screenSaver` level reliably and `CGEventTap` will fail.

2. **`NSVisualEffectView.state = .active`** is mandatory. The default `.followsWindowActiveState` renders as a flat color because `orderFrontRegardless()` never makes the window key.

3. **Use `orderFrontRegardless()`**, not `makeKeyAndOrderFront(_:)`. The former shows the window without the app needing to be active and without stealing focus.

4. **`window.level = .screenSaver`** must be set in code after programmatic window creation. Not in a storyboard.

5. **`collectionBehavior`** must be exactly `[.canJoinAllSpaces, .stationary, .ignoresCycle]`. Do NOT include `.fullScreenAuxiliary` — it is a split-view tiling flag, not a float-above-all-spaces flag.

6. **`screen.frame` not `screen.visibleFrame`** — `visibleFrame` excludes the menu bar and Dock. We want full coverage.

7. **`NSWindow` subclass** — override `canBecomeKey` to return `true`. A `.borderless` window returns `false` by default, preventing click events from being delivered to subviews (e.g. the skip button) via the responder chain.

8. **CGEventTap callback** must be a file-scope C function. It cannot be a Swift closure or instance method. Communicate with the rest of the app via `DispatchQueue.main.async` and the singleton `BreakScheduler.shared`.

9. **`DispatchSourceTimer` cleanup** — always call `.cancel()` before releasing the timer. A suspended `DispatchSourceTimer` that is cancelled must be resumed once before deallocation (or just always call `.resume()` immediately after creating the timer before storing it). Failure causes `EXC_BAD_INSTRUCTION`.

10. **Multi-monitor** — `NSScreen.screens[0]` is not the primary display. `NSScreen.main` is the screen of the currently active window. Create one controller per entry in `NSScreen.screens`; set each window's frame to `screen.frame`.

---

*Plan version 1.1 — incorporates CGEventTap input blocking, emergency escape hatch, and DispatchSourceTimer. Prepared for implementation by Claude Opus or equivalent.*
