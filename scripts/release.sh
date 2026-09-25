#!/bin/bash
# Build a signed, notarized, stapled AudioPaper release: build/release/AudioPaper-<version>.dmg
#
# Run on the maintainer's Mac, which holds the "Developer ID Application" certificate for the team in
# project.yml. Needs, in the environment:
#   APPLE_ID, APPLE_PASSWORD (an app-specific password), APPLE_TEAM_ID   — for notarytool
#   FANART_PROJECT_KEY — the fanart.tv project key the app ships with. If unset, it's read from the
#                        repo's .env (FAN_ART_API_KEY). It goes into the built app's Info.plist only;
#                        it is never written to the repository.
#
#   set -a; source ~/.config/brew-browser/signing.env; set +a   # or wherever your credentials live
#   scripts/release.sh
#
# Flow: archive (Release) → export with Developer ID (app, widget extension and Sparkle's helpers, hardened
#       runtime) → verify signatures and entitlements → notarize the app → staple
#       → Sparkle update zip, signed with the EdDSA key (`generate_keys --account AudioPaper`, in the login
#         Keychain) → feed entry in site/static/appcast.xml
#       → disk image with an Applications link → sign → notarize → staple → checksums.
# Afterwards: publish the GitHub release with the .dmg and .zip, THEN push the feed (it points at the zip).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${APPLE_ID:?set APPLE_ID (see the header of this script)}"
: "${APPLE_PASSWORD:?set APPLE_PASSWORD (an app-specific password)}"
: "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
if [ -z "${FANART_PROJECT_KEY:-}" ] && [ -f .env ]; then
  FANART_PROJECT_KEY="$(grep -E '^FAN_ART_API_KEY=' .env | head -1 | cut -d= -f2- | tr -d '"' || true)"
fi
: "${FANART_PROJECT_KEY:?set FANART_PROJECT_KEY, or FAN_ART_API_KEY in .env}"

TEAM="$(grep -m1 'DEVELOPMENT_TEAM:' project.yml | awk '{print $2}')"
[ "$TEAM" = "$APPLE_TEAM_ID" ] || { echo "project.yml team ($TEAM) doesn't match APPLE_TEAM_ID"; exit 1; }
IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM)" | head -1 | awk '{print $2}')"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application certificate for team $TEAM in the Keychain"; exit 1; }
VERSION="$(grep -m1 'MARKETING_VERSION:' project.yml | tr -d '" ' | cut -d: -f2)"
BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | tr -d '" ' | cut -d: -f2)"

OUT="$ROOT/build/release"
PACKAGES="$ROOT/build/SourcePackages"
SPARKLE_BIN="$PACKAGES/artifacts/sparkle/Sparkle/bin"
ZIP="$OUT/AudioPaper-$VERSION.zip"
ARCHIVE="$OUT/AudioPaper.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/AudioPaper.app"
DMG="$OUT/AudioPaper-$VERSION.dmg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT" && mkdir -p "$OUT"

notarize() {
  xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID" \
    --wait --output-format json | tee "$WORK/notary.json" | grep -q '"status" *: *"Accepted"' || {
      echo "Notarization failed:"; cat "$WORK/notary.json"
      id="$(sed -nE 's/.*"id" *: *"([^"]+)".*/\1/p' "$WORK/notary.json" | head -1)"
      [ -n "$id" ] && xcrun notarytool log "$id" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID"
      exit 1
    }
}

echo "==> AudioPaper $VERSION ($BUILD), team $TEAM"
xcodegen generate --quiet

echo "==> archive (Release)"
xcodebuild -project AudioPaper.xcodeproj -scheme AudioPaper -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$ARCHIVE" -clonedSourcePackagesDirPath "$PACKAGES" \
  -allowProvisioningUpdates -quiet \
  FANART_PROJECT_KEY="$FANART_PROJECT_KEY" archive

echo "==> export with Developer ID"
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates -quiet

echo "==> verify"
codesign --verify --deep --strict --verbose=2 "$APP"
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
for helper in "$SPARKLE_FW" "$SPARKLE_FW/Versions/B/Autoupdate" "$SPARKLE_FW/Versions/B/Updater.app" \
  "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc"; do
  # Captured first: with pipefail, `grep -q` closing the pipe early would read as a failure.
  info="$(codesign -dvv "$helper" 2>&1)"
  grep -q "Authority=Developer ID Application" <<<"$info" || { echo "$helper: not Developer ID signed"; exit 1; }
done
for bundle in "$APP" "$APP/Contents/PlugIns/AudioPaperWidgets.appex"; do
  info="$(codesign -dvv "$bundle" 2>&1)"
  grep -q "Authority=Developer ID Application" <<<"$info" || { echo "$bundle: not Developer ID signed"; exit 1; }
  grep -q "flags=.*runtime" <<<"$info" || { echo "$bundle: hardened runtime missing"; exit 1; }
  codesign -d --entitlements - --xml "$bundle" 2>/dev/null | grep -q "com.apple.security.app-sandbox" \
    || { echo "$bundle: not sandboxed"; exit 1; }
done
[ "$(/usr/libexec/PlistBuddy -c 'Print :FanartTVProjectKey' "$APP/Contents/Info.plist")" = "$FANART_PROJECT_KEY" ] \
  || { echo "fanart.tv project key missing from the build"; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION" ] \
  || { echo "version mismatch"; exit 1; }

echo "==> notarize the app (waits for Apple)"
ditto -c -k --keepParent "$APP" "$WORK/AudioPaper.zip"
notarize "$WORK/AudioPaper.zip"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> Sparkle update: zip, EdDSA signature, feed entry"
[ -x "$SPARKLE_BIN/sign_update" ] || { echo "Sparkle tools missing at $SPARKLE_BIN"; exit 1; }
ditto -c -k --keepParent "$APP" "$ZIP"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account AudioPaper -p "$ZIP")"
[ -n "$SIGNATURE" ] || { echo "sign_update produced no signature"; exit 1; }
python3 "$ROOT/scripts/appcast.py" "$VERSION" "$BUILD" "$ZIP" "$SIGNATURE" ${RELEASE_NOTES_HTML:+"$RELEASE_NOTES_HTML"}

echo "==> disk image"
mkdir -p "$WORK/dmg"
ditto "$APP" "$WORK/dmg/AudioPaper.app"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -volname "AudioPaper $VERSION" -srcfolder "$WORK/dmg" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "==> notarize the disk image (waits for Apple)"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > "AudioPaper-$VERSION.sha256")
echo
echo "==> done: $DMG and $ZIP; site/static/appcast.xml updated"
cat "$OUT/AudioPaper-$VERSION.sha256"
echo "Next: publish the GitHub release v$VERSION with both files, then commit and push the feed."
