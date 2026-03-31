# EyeRest

A lightweight macOS menu-bar utility that reminds you to rest your eyes using the 20‑20‑20 rule: every 20 minutes, take a short break and look away from the screen.

Table of Contents
- Features
- Requirements
- Quick start
- Build from source
- Usage
- Configuration (UserDefaults keys)
- Developer notes / important files
- Packaging & distribution
- Troubleshooting
- Contributing
- License & acknowledgments

Features
- Stable, flicker-free full-screen blur overlay (per-screen)
- Shows above all apps (including full‑screen) using `.screenSaver` window level
- Keyboard & mouse input blocking during breaks (Accessibility permission required)
- Emergency-escape chord: Ctrl + Option + Command + Shift + E
- Multi-monitor support (one overlay per NSScreen)
- Configurable interval and break duration

Requirements
- macOS 13.0+ (Info.plist minimum)
- Accessibility permission (for the CGEventTap input blocker)
- Screen Recording permission may be required on some macOS versions for reliable screenshots

Quick start (user)
1. Download EyeRest.app from Releases (or build from source below).
2. Copy to /Applications
3. Open the app and grant Accessibility (and Screen Recording if prompted).
4. The app runs from the menu bar — use the menu to pause or change interval.

Build from source
- Open the Xcode project: `open EyeRest.xcodeproj` and build (⌘R)
- Command-line build (Release):

```bash
xcodebuild -project EyeRest.xcodeproj -scheme EyeRest -configuration Release clean build
```

Usage
- Menu bar popover shows next break, lets you trigger a break now, pause the schedule, and change interval/duration.
- During a break a full-screen static blurred snapshot is shown with a countdown ring.
- Emergency escape: press Ctrl+Option+Cmd+Shift+E to end a break early.

Configuration (UserDefaults)
The app stores settings in `~/Library/Preferences/<bundle-id>.plist` (example bundle id: `com.yourname.EyeRest`). Use `defaults` to read/write values.

Important keys (as used in the code):
- `breakIntervalMinutes` (Int) — interval between breaks in minutes (default: 20)
- `breakDurationSeconds` (Int) — break length in seconds (default: 30)
- `countdownDuration` (Int) — deprecated but still referenced by the UI countdown ring
- `paused` (Bool) — pause/resume break scheduling

Examples:
```bash
# Set 30-minute interval
defaults write com.yourname.EyeRest breakIntervalMinutes -int 30

# Set 15-second break duration
defaults write com.yourname.EyeRest breakDurationSeconds -int 15

# Pause breaks
defaults write com.yourname.EyeRest paused -bool true

# Quick test: 1-minute interval + 5-second break
defaults write com.yourname.EyeRest breakIntervalMinutes -int 1
defaults write com.yourname.EyeRest breakDurationSeconds -int 5
```

Developer notes / important files
- Language: Swift (SwiftUI + AppKit hybrid)
- Key code locations:
  - App entry & lifecycle: `EyeRest/App/EyeRestApp.swift`, `EyeRest/App/AppDelegate.swift`
  - Scheduler: `EyeRest/Scheduling/BreakScheduler.swift`
  - Overlay windows and blur: `EyeRest/Overlay/OverlayWindowController.swift`, `EyeRest/Overlay/OverlayView.swift`
  - Input blocking (CGEventTap): `EyeRest/Input/InputBlocker.swift`
  - Menu bar UI: `EyeRest/MenuBar/MenuBarView.swift`
  - Preferences wrapper: `EyeRest/Preferences/UserPreferences.swift`
- Blur implementation:
  - Captures a screenshot per screen using `CGDisplayCreateImage()` and applies a Core Image `CIGaussianBlur` (radius ≈ 30) to produce a static, flicker-free overlay (see `BLUR_IMPLEMENTATION.md`).
- Overlay window:
  - Uses `NSWindow.Level.screenSaver` and collection behavior `.canJoinAllSpaces` to appear above everything.
- Input blocking:
  - Uses `CGEvent.tapCreate` at `.cgAnnotatedSessionEventTap` to intercept keyboard/mouse events while a break is active.

Packaging & distribution
- For personal use: copy the built `.app` to `/Applications` and run `xattr -cr /Applications/EyeRest.app` if Gatekeeper blocks it.
- For public distribution: sign, enable hardened runtime, build a signed DMG, and notarize via Apple's notarization flow. See `PACKAGING.md` for detailed instructions and sample GitHub Actions workflow.

Troubleshooting
- Accessibility not granted: System Settings → Privacy & Security → Accessibility → Enable EyeRest
- Screen Recording prompt: EyeRest triggers a check on first launch using ScreenCaptureKit to show the Screen Recording permission dialog. If denied, enable System Settings → Privacy & Security → Screen Recording.
- Gatekeeper: `xattr -cr /Applications/EyeRest.app` or use System Settings → Privacy & Security → Open Anyway.
- If the blur flickers, check `BLUR_IMPLEMENTATION.md` and `TROUBLESHOOTING.md` for mitigation strategies (screenshot-based blur is the recommended approach).

Contributing
- Bug reports and pull requests welcome.
- Open an issue describing the problem and include macOS version and exact steps to reproduce.
- Follow code style in the repository; prefer small, focused PRs.

License & acknowledgments
- License: MIT
- Built with Swift, SwiftUI, AppKit, Core Image. Thanks to the open-source community for examples and guidance.

If you want a short checklist or a quick demo script, see `PACKAGING.md` and `BLUR_IMPLEMENTATION.md` for more details.
