# EyeRest - Blur Flickering Troubleshooting

## Current Status
The app has been modified to separate the blur layer from SwiftUI updates, but flickering may still occur.

## What Has Been Tried

### ✅ Separated blur from SwiftUI
- NSVisualEffectView created once at AppKit level
- SwiftUI content layer sits on top
- No animations on countdown
- `wantsLayer = false` on hosting view

### Current Architecture
```
NSWindow (.screenSaver level)
└── NSView container
    ├── NSVisualEffectView (.hudWindow, .behindWindow) ← Static
    ├── NSView (dark tint)                              ← Static
    └── NSHostingView (SwiftUI content)                 ← Updates every 1s
        └── Eye icon, text, countdown number
```

## If Still Flickering

The issue may be fundamental to NSVisualEffectView behavior at high window levels. Try these alternatives:

### Option 1: Solid Semi-Transparent Overlay (Simplest)
Replace blur with solid color:
```swift
// Instead of NSVisualEffectView
let overlay = NSView(frame: screen.frame)
overlay.wantsLayer = true
overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
```
**Pros:** No flickering, very stable  
**Cons:** Not as visually appealing as blur

### Option 2: Screenshot + Static Blur
Capture and blur once at break start:
```swift
// In setupWindow() or showOverlay()
let screenshot = CGWindowListCreateImage(CGRect.infinite, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
let ciImage = CIImage(cgImage: screenshot!)
let blurred = ciImage.applyingGaussianBlur(sigma: 25)
// Display blurred image
```
**Pros:** No live updates, perfectly stable  
**Cons:** Shows desktop state from break start, not current

### Option 3: Different Material
Try other NSVisualEffectView materials that may be less sensitive:
```swift
blur View.material = .fullScreenUI  // Very dark, immersive
// or
blurView.material = .sidebar        // Lighter
```

### Option 4: Update Less Frequently
Reduce countdown updates to every 2-3 seconds instead of every second to minimize flicker frequency.

## Testing Checklist

Please observe and report:
- [ ] Does blur appear at all during break?
- [ ] How often does it flicker? (Once per second? Continuous?)
- [ ] How severe? (Brief flash? Complete re-render? Screen goes black/yellow?)
- [ ] Does text/countdown update smoothly?
- [ ] Any console errors visible?

## Quick Fixes to Test

### Disable countdown entirely
```bash
defaults write com.yourname.EyeRest countdownDuration -int 30
# Then modify OverlayView to show static "30s" instead of live countdown
```

### Try different blur material
Edit `EyeRest/Overlay/OverlayWindowController.swift` line with `blurView.material`:
- `.hudWindow` (current)
- `.fullScreenUI` (darker)
- `.sidebar` (lighter)
- `.popover` (medium)

## Contact Info for Debugging
If flickering persists, please describe exactly what you see and I can provide a targeted fix.
