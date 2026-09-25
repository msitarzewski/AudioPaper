#!/bin/bash
# Build AudioPaper, install it to /Applications, and relaunch it.
#
# Widgets only appear in the widget gallery for apps installed in an Applications folder, so use this
# (rather than running from Xcode's build folder) when working on the widgets.
#
#   scripts/install.sh            # Debug build
#   scripts/install.sh Release    # Release build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-Debug}"
DERIVED="$ROOT/build/DerivedData"
BUILT="$DERIVED/Build/Products/$CONFIGURATION/AudioPaper.app"
TARGET="/Applications/AudioPaper.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cd "$ROOT"
xcodegen generate --quiet

# Sign with the same Developer ID certificate as releases when this Mac has it. The Keychain ties each saved
# API key to the app's signature, so alternating Apple Development builds and Developer ID releases asks for
# the login password once per key on every switch; one signature means it never asks. Without the
# certificate (contributors), Xcode's automatic signing is used as before.
TEAM="$(grep -m1 'DEVELOPMENT_TEAM:' project.yml | awk '{print $2}')"
SIGNING=()
if security find-identity -v -p codesigning | grep "Developer ID Application" | grep -q "($TEAM)"; then
  SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" PROVISIONING_PROFILE_SPECIFIER=)
fi

xcodebuild -project AudioPaper.xcodeproj -scheme AudioPaper -configuration "$CONFIGURATION" -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build ${SIGNING[@]+"${SIGNING[@]}"}

# Quit the running copy cleanly so it saves its state (Mini Player position and open state).
if pgrep -xq AudioPaper; then
  osascript -e 'tell application "AudioPaper" to quit' || true
  for _ in {1..20}; do pgrep -xq AudioPaper || break; sleep 0.25; done
fi

rm -rf "$TARGET"
ditto "$BUILT" "$TARGET"
# One registered copy only, so the widget gallery and Launch Services find the installed app.
"$LSREGISTER" -u "$BUILT" 2>/dev/null || true
"$LSREGISTER" -f -R "$TARGET"

# macOS keeps a widget extension running across app updates; stop it so the new build's widgets load.
pkill -x AudioPaperWidgets 2>/dev/null || true

open "$TARGET"
echo "Installed $CONFIGURATION build to $TARGET and relaunched."
