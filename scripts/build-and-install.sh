#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/EyeRest.xcodeproj"
SCHEME="EyeRest"
CONFIGURATION="Release"

echo "Repo root: $REPO_ROOT"

echo "Cleaning Xcode build for $SCHEME ($CONFIGURATION)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" clean

# Remove DerivedData for EyeRest
echo "Removing DerivedData (if any) for EyeRest..."
rm -rf ~/Library/Developer/Xcode/DerivedData/EyeRest-* || true

# Build
echo "Building release..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" clean build

# Locate built .app
BUILD_APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/$CONFIGURATION/EyeRest.app" -print -quit)
if [[ -z "$BUILD_APP" ]]; then
  echo "Built app not found in DerivedData. Searching in repo build/ folder..."
  BUILD_APP="$REPO_ROOT/build/EyeRest.app"
  if [[ ! -d "$BUILD_APP" ]]; then
    echo "Error: Built app not found. Please open Xcode and build manually."
    exit 1
  fi
fi

echo "Built app found at: $BUILD_APP"

TARGET="/Applications/EyeRest.app"

if [[ -d "$TARGET" ]]; then
  echo "Removing existing $TARGET (requires sudo)..."
  sudo rm -rf "$TARGET"
fi

echo "Copying $BUILD_APP to /Applications (may ask for password)..."
sudo cp -R "$BUILD_APP" /Applications/

echo "Applying ad-hoc codesign (to avoid Gatekeeper warnings)..."
sudo codesign --force --deep --sign - "$TARGET" || true

echo "Clearing quarantine attribute..."
sudo xattr -cr "$TARGET" || true

echo "Installed EyeRest to $TARGET"
echo "Please grant Accessibility permission to EyeRest in System Settings → Privacy & Security → Accessibility"
