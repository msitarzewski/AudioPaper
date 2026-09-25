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
xcodebuild -project AudioPaper.xcodeproj -scheme AudioPaper -configuration "$CONFIGURATION" -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build

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

open "$TARGET"
echo "Installed $CONFIGURATION build to $TARGET and relaunched."
