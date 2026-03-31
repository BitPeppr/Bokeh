# EyeRest - Blur Implementation

## Final Solution: Static Screenshot Blur

The app uses a **screenshot-based blur** that is captured once when each break starts. This provides a completely stable, flicker-free blur effect.

## How It Works

1. **When break starts:** App captures a screenshot of the current screen using `CGDisplayCreateImage()`
2. **Blur applied:** Screenshot is processed with Core Image's `CIGaussianBlur` filter (30px radius)
3. **Display:** Blurred image is displayed as a static `NSImageView` background
4. **Content overlaid:** SwiftUI content (text, countdown, skip button) sits on top
5. **No updates:** The blur image remains completely static during the entire break - only the countdown text updates

## Advantages

✅ **Zero flickering** - Image is captured once and never changes  
✅ **Stable rendering** - No compositor recalculations  
✅ **Clean separation** - Blur layer independent from SwiftUI updates  
✅ **Predictable performance** - Same behavior on all hardware  
✅ **Multi-monitor support** - Each screen gets its own screenshot and blur

## Technical Architecture

```
NSWindow (.screenSaver level)
└── NSView container
    ├── NSImageView (blurred screenshot) ← Static, captured at break start
    ├── NSView (dark tint overlay)       ← Static
    └── NSHostingView (SwiftUI)          ← Updates countdown every 1s
        └── Eye icon, text, countdown
```

## Trade-offs

**Pro:** Completely eliminates flickering  
**Con:** Shows desktop state from when break started, not live updates

This is the optimal solution for a break reminder app - users shouldn't be working during the break anyway, so a static blur of their pre-break desktop is perfectly acceptable and provides the best UX.

## Code Location

Implementation in `EyeRest/Overlay/OverlayWindowController.swift`:
- `showOverlay()` - Captures screenshot and creates blur when break starts
- `createBlurredScreenshot()` - Uses Core Image to blur the captured screenshot
