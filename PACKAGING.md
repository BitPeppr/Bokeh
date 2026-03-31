# EyeRest Packaging Guide

## Packaging Options

### Option 1: Simple .app Distribution (Recommended for Personal Use)

This is the easiest method for sharing with yourself or a few trusted users.

#### Steps:

1. **Build the Release version:**

   ```bash
   cd /Users/martinchen/Desktop/Project/eye-rest
   xcodebuild -project EyeRest.xcodeproj -scheme EyeRest -configuration Release clean build
   ```

2. **Find the built app:**

   ```bash
   BUILD_PATH="/Users/martinchen/Library/Developer/Xcode/DerivedData/EyeRest-*/Build/Products/Release/EyeRest.app"
   ```

3. **Copy to Applications:**

   ```bash
   cp -R "$(echo $BUILD_PATH)" /Applications/
   ```

4. **Sign it (ad-hoc):**

   ```bash
   codesign --force --deep --sign - /Applications/EyeRest.app
   xattr -cr /Applications/EyeRest.app  # Remove quarantine
   ```

5. **Create a DMG (optional):**
   ```bash
   hdiutil create -volname "EyeRest" -srcfolder /Applications/EyeRest.app -ov -format UDZO EyeRest.dmg
   ```

**Distribution:** Share the .app or .dmg file. Recipients need to:

- Copy to Applications
- Run `xattr -cr /Applications/EyeRest.app` to remove quarantine
- Grant Accessibility permission when prompted

---

### Option 2: Notarized Distribution (For Public Distribution)

If you want to distribute publicly without Gatekeeper warnings, you need:

- Apple Developer Account ($99/year)
- Developer ID certificate
- Notarization via Apple

#### Steps:

1. **Update code signing settings in Xcode:**
   - Open project settings
   - Signing & Capabilities → Team: Select your team
   - Code Sign Identity: "Developer ID Application"
   - Enable Hardened Runtime

2. **Update entitlements for hardened runtime:**

   ```xml
   <!-- EyeRest/Resources/EyeRest.entitlements -->
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.security.app-sandbox</key>
       <false/>
       <!-- Required for hardened runtime -->
       <key>com.apple.security.automation.apple-events</key>
       <true/>
   </dict>
   </plist>
   ```

3. **Build with Developer ID:**

   ```bash
   xcodebuild -project EyeRest.xcodeproj -scheme EyeRest -configuration Release \
     CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
     ENABLE_HARDENED_RUNTIME=YES \
     clean build
   ```

4. **Create signed DMG:**

   ```bash
   # Create DMG
   hdiutil create -volname "EyeRest" -srcfolder "path/to/EyeRest.app" \
     -ov -format UDZO EyeRest-unsigned.dmg

   # Sign DMG
   codesign --force --sign "Developer ID Application: Your Name (TEAMID)" \
     EyeRest-unsigned.dmg -o EyeRest.dmg
   ```

5. **Notarize with Apple:**

   ```bash
   # Upload for notarization
   xcrun notarytool submit EyeRest.dmg \
     --apple-id "your@email.com" \
     --team-id "TEAMID" \
     --password "app-specific-password" \
     --wait

   # Staple the notarization ticket
   xcrun stapler staple EyeRest.dmg
   ```

6. **Verify:**
   ```bash
   spctl -a -v EyeRest.dmg  # Should say "accepted"
   ```

---

### Option 3: Homebrew Cask (For Tech-Savvy Users)

Create a homebrew cask for easy installation via `brew install --cask eyerest`

#### Steps:

1. **Host the DMG somewhere permanent** (GitHub Releases, your own server, etc.)

2. **Create a cask formula:**

   ```ruby
   # homebrew-eyerest/Casks/eyerest.rb
   cask "eyerest" do
     version "1.0.0"
     sha256 "abc123..."  # SHA256 of your DMG

     url "https://github.com/yourname/eyerest/releases/download/v#{version}/EyeRest.dmg"
     name "EyeRest"
     desc "Eye break reminder with full-screen blur overlay"
     homepage "https://github.com/yourname/eyerest"

     app "EyeRest.app"

     postflight do
       system_command "/usr/bin/open",
         args: ["-a", "System Settings", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
       puts "Please grant EyeRest Accessibility permission in System Settings"
     end

     zap trash: [
       "~/Library/Preferences/com.yourname.EyeRest.plist",
     ]
   end
   ```

3. **Submit to homebrew-cask or create your own tap**

---

### Option 4: GitHub Releases (Recommended for Open Source)

1. **Create a GitHub repo** and push your code

2. **Set up GitHub Actions for automated builds:**

   ```yaml
   # .github/workflows/release.yml
   name: Release

   on:
     push:
       tags:
         - "v*"

   jobs:
     build:
       runs-on: macos-latest
       steps:
         - uses: actions/checkout@v3

         - name: Build
           run: |
             xcodebuild -project EyeRest.xcodeproj \
               -scheme EyeRest \
               -configuration Release \
               clean build

         - name: Package
           run: |
             cp -R ~/Library/Developer/Xcode/DerivedData/EyeRest-*/Build/Products/Release/EyeRest.app .
             hdiutil create -volname "EyeRest" -srcfolder EyeRest.app -ov -format UDZO EyeRest.dmg

         - name: Release
           uses: softprops/action-gh-release@v1
           with:
             files: EyeRest.dmg
   ```

3. **Tag a release:**

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

4. **GitHub Actions will automatically build and create a release**

---

## Quick Package for Personal Use

Here's a one-liner to package for yourself:

```bash
cd /Users/martinchen/Desktop/Project/eye-rest && \
xcodebuild -project EyeRest.xcodeproj -scheme EyeRest -configuration Release clean build && \
BUILD_APP=$(find ~/Library/Developer/Xcode/DerivedData/EyeRest-*/Build/Products/Release -name "EyeRest.app" -type d | head -1) && \
cp -R "$BUILD_APP" ~/Desktop/ && \
codesign --force --deep --sign - ~/Desktop/EyeRest.app && \
echo "✓ EyeRest.app packaged on Desktop"
```

Then share `~/Desktop/EyeRest.app` with others.

---

## Launch at Login Setup

After installation, users can set up auto-launch:

### Method 1: System Settings (easiest)

1. System Settings → General → Login Items
2. Click "+" and select EyeRest.app

### Method 2: launchd (most reliable, auto-restart on crash)

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

---

## Troubleshooting Gatekeeper

If macOS blocks the app with "cannot be opened because it is from an unidentified developer":

```bash
# Remove quarantine attribute
xattr -cr /Applications/EyeRest.app

# Or allow it in System Settings
System Settings → Privacy & Security → Security → "Open Anyway"
```

---

## Distribution Checklist

- [ ] Build Release configuration
- [ ] Test on a clean Mac (if possible)
- [ ] Sign with `codesign`
- [ ] Create DMG or ZIP
- [ ] Test installation from package
- [ ] Verify Accessibility permission prompt works
- [ ] Write installation instructions
- [ ] Include README with screenshots
- [ ] Specify macOS version requirements (13.0+)
