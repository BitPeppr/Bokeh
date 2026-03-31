# EyeRest

A macOS menu bar app that reminds you to rest your eyes using the 20-20-20 rule: every 20 minutes, look at something 20 feet away for 20 seconds.

## Features

- 🖥️ **Full-screen blur overlay** covering all displays during breaks
- ⬆️ **Appears above everything** including full-screen apps and Mission Control spaces
- ⌨️ **Keyboard shortcut blocking** during breaks (requires Accessibility permission)
- 🎯 **Flicker-free blur** using static screenshot technology
- 📺 **Multi-monitor support** — all screens covered simultaneously
- 👻 **Menu bar only** — no Dock icon or Cmd+Tab presence
- ⚙️ **Configurable intervals** — 10, 20, 30, 45, or 60 minutes
- 🔘 **Optional skip button** — can be disabled for discipline
- 🚨 **Emergency escape** — Ctrl+Option+Cmd+Shift+E during a break
- 😴 **Smart sleep/wake handling** — resets timer after system wake

## The 20-20-20 Rule

Every 20 minutes, look at something 20 feet away for 20 seconds. This helps reduce eye strain from prolonged screen use.

## Requirements

- macOS 13 Ventura or later
- Accessibility permission (for keyboard blocking during breaks)

## Installation

### Quick Start

1. Download `EyeRest.app` from releases
2. Drag to Applications folder
3. Right-click and select "Open" (first time only)
4. Grant Accessibility permission when prompted
5. Menu bar icon (👁) appears and breaks start automatically

### Building from Source

```bash
git clone <repository>
cd eye-rest
open EyeRest.xcodeproj
# Build and run in Xcode (⌘R)
```

## Usage

### Menu Bar Options

- **Next break in X:XX** — countdown to next break
- **Take break now** — trigger immediate break
- **Allow skip button** — show/hide skip button during breaks  
- **Pause schedule** — temporarily disable automatic breaks
- **Interval** — choose break frequency (10-60 min)
- **Emergency exit reminder** — ⌃⌥⌘⇧E chord

### Emergency Escape

If you absolutely must exit a break early (emergency call, etc.):

**Press:** `Ctrl + Option + Cmd + Shift + E`

This chord is intentionally difficult to trigger accidentally.

## Technical Details

### Blur Implementation
EyeRest uses a **screenshot-based blur** that captures the screen once when the break starts, applies a Gaussian blur filter, and displays it as a static image. This eliminates all flickering and provides a stable, smooth overlay. See [BLUR_IMPLEMENTATION.md](BLUR_IMPLEMENTATION.md) for details.

### Window Level
The overlay runs at `.screenSaver` level (101), above the menu bar and Dock, with `.canJoinAllSpaces` behavior to appear across all Mission Control spaces and full-screen apps.

### Input Blocking
A `CGEventTap` intercepts keyboard and mouse events during breaks. Requires Accessibility permission. The emergency escape chord (⌃⌥⌘⇧E) is always honored.

## Configuration

Settings are stored in `~/Library/Preferences/com.yourname.EyeRest.plist`. You can also set them via command line:

```bash
# Set 30-minute interval
defaults write com.yourname.EyeRest breakIntervalMinutes -int 30

# Set 20-second countdown
defaults write com.yourname.EyeRest countdownDuration -int 20

# Enable skip button
defaults write com.yourname.EyeRest skipEnabled -bool true

# Pause breaks
defaults write com.yourname.EyeRest paused -bool true
```

## Launch at Login

### Method 1: System Settings (easiest)
1. System Settings → General → Login Items
2. Click "+" and select EyeRest.app

### Method 2: launchd (auto-restart on crash)

Create `~/Library/LaunchAgents/com.yourname.eyerest.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.yourname.eyerest</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/EyeRest.app/Contents/MacOS/EyeRest</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.yourname.eyerest.plist
```

## Troubleshooting

### "Cannot be opened because it is from an unidentified developer"
```bash
xattr -cr /Applications/EyeRest.app
```

Or: System Settings → Privacy & Security → Security → "Open Anyway"

### Input blocking not working
Ensure Accessibility permission is granted:  
System Settings → Privacy & Security → Accessibility → Enable EyeRest

### App doesn't appear in menu bar
Check that `LSUIElement` is set in Info.plist (it should be by default)

## Packaging & Distribution

See [PACKAGING.md](PACKAGING.md) for detailed instructions on creating distributable builds, DMGs, notarization, and Homebrew casks.

## Architecture

```
EyeRest/
├── App/                   # @main entry, AppDelegate
├── Scheduling/            # Timer logic, sleep/wake handling  
├── Overlay/               # Window management, blur, UI
├── Input/                 # CGEventTap keyboard blocking
├── MenuBar/               # Menu bar popover UI
├── Preferences/           # UserDefaults wrapper
└── Resources/             # Info.plist, entitlements, assets
```

## License

MIT

## Acknowledgments

Built with Swift, SwiftUI, and AppKit. Blur implementation uses Core Image's Gaussian blur filter applied to screen captures.
