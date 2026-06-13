#!/usr/bin/env bash
set -euo pipefail

# NetCheck — build, (ad-hoc) sign, and package into a DMG.
# Runs on macOS *with Xcode* (your laptop or GitHub Actions). Cannot run on a CLT-only Mac.
#
# Env overrides:
#   SIGN_IDENTITY   codesign identity. Default "-" (ad-hoc).
#                   Later (with a $99 account): "Developer ID Application: Your Name (TEAMID)".
#   SPARKLE_BIN     path to Sparkle's bin/ (with sign_update). If set, prints the EdDSA signature.
#   NOTARIZE=1      with a Developer ID identity, runs notarytool + stapler (needs NOTARY_PROFILE).
#
# The ONLY thing that changes when you buy the Apple Developer account is SIGN_IDENTITY
# (and setting NOTARIZE=1). Everything else — Sparkle, the DMG, the cask — stays identical.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="NetCheck"
SCHEME="NetCheck"
CONFIG="Release"
DERIVED="$ROOT/build"
DIST="$ROOT/dist"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "▶︎ Generating Xcode project (xcodegen)…"
xcodegen generate

echo "▶︎ Building $CONFIG…"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  build | tail -8

APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[ -d "$APP" ] || { echo "✗ Build product not found at $APP"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "▶︎ Version $VERSION"

# --- Sign Sparkle's nested components, innermost first, NO --deep ---
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  echo "▶︎ Signing Sparkle components…"
  RUNTIME=(--options runtime --timestamp)
  for xpc in \
    "$FW/Versions/B/XPCServices/Installer.xpc" \
    "$FW/Versions/B/XPCServices/Downloader.xpc"; do
    [ -d "$xpc" ] && codesign -f -s "$SIGN_IDENTITY" "${RUNTIME[@]}" "$xpc"
  done
  [ -e "$FW/Versions/B/Autoupdate" ]     && codesign -f -s "$SIGN_IDENTITY" "${RUNTIME[@]}" "$FW/Versions/B/Autoupdate"
  [ -d "$FW/Versions/B/Updater.app" ]    && codesign -f -s "$SIGN_IDENTITY" "${RUNTIME[@]}" "$FW/Versions/B/Updater.app"
  codesign -f -s "$SIGN_IDENTITY" "${RUNTIME[@]}" "$FW"
fi

echo "▶︎ Signing app…"
codesign -f -s "$SIGN_IDENTITY" --options runtime --timestamp \
  --entitlements "App/NetCheck.entitlements" "$APP"

# --- DMG ---
mkdir -p "$DIST"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG" "$DIST"/rw.*.dmg          # clear stale temps that otherwise make create-dmg fail
echo "▶︎ Creating DMG…"
create-dmg \
  --volname "$APP_NAME" \
  --window-size 500 320 \
  --icon "$APP_NAME.app" 120 170 \
  --app-drop-link 380 170 \
  "$DMG" "$APP" >/dev/null 2>&1 || true
rm -f "$DIST"/rw.*.dmg

# Fallback: a styled DMG needs Finder/AppleScript, which can fail headless. A plain hdiutil DMG
# is just as installable, so guarantee one lands either way.
if [ ! -f "$DMG" ]; then
  echo "▶︎ create-dmg didn't produce a DMG; building a plain one via hdiutil…"
  STAGE="$DIST/.stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
fi
[ -f "$DMG" ] || { echo "✗ DMG creation failed"; exit 1; }
echo "✓ $DMG"

# --- Optional: notarize (only meaningful with a Developer ID identity) ---
if [ "${NOTARIZE:-0}" = "1" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  echo "▶︎ Notarizing…"
  xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:?set NOTARY_PROFILE}" --wait
  xcrun stapler staple "$DMG"
fi

# --- Optional: Sparkle EdDSA signature (for the appcast) ---
if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/sign_update" ]; then
  echo "▶︎ Sparkle signature for $DMG:"
  "$SPARKLE_BIN/sign_update" "$DMG"
fi

echo "✓ Done → $DMG"
