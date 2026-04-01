import Cocoa
import Combine

// Emergency escape: Ctrl + Option + Cmd + Shift + E (keycode 14)
private let kEmergencyModifiers: CGEventFlags = [.maskControl, .maskAlternate,
                                                  .maskCommand, .maskShift]
private let kEmergencyKeyCode: CGKeyCode = 14  // 'E'

private func hazelEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Handle tap disabled events
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon = refcon {
            let blocker = Unmanaged<InputBlocker>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                blocker.reEnableTap()
            }
        }
        return Unmanaged.passRetained(event)
    }

    // Pass through system/null events that are not user-input types
    let blockedTypes: Set<CGEventType> = [.keyDown, .keyUp, .flagsChanged,
                                          .scrollWheel, .leftMouseDown,
                                          .rightMouseDown, .otherMouseDown]
    guard blockedTypes.contains(type) else {
        return Unmanaged.passRetained(event)
    }

    // Check for emergency escape chord on keyDown
    if type == .keyDown {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection([.maskControl, .maskAlternate,
                                              .maskCommand, .maskShift])
        if keyCode == kEmergencyKeyCode && flags == kEmergencyModifiers {
            DispatchQueue.main.async { BreakScheduler.shared.endBreakEarly() }
            return Unmanaged.passRetained(event)
        }
    }

    // Discard all other events during the break
    return nil
}

final class InputBlocker {
    static let shared = InputBlocker()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeScheduler()
    }

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
                case .idle: self?.disable()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Enable / Disable

    func enable() {
        guard AXIsProcessTrusted() else { return }
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eyeRestEventCallback,
            userInfo: selfPtr
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

    func reEnableTap() {
        if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}
