#!/bin/zsh
# Build Hyperday for the iPhone 17 Pro Max simulator and run it. Nothing touches your real iPhone.
#   zsh tools/sim.sh
set -e
cd "$(dirname "$0")/.."
NAME="iPhone 17 Pro Max"
UDID=$(xcrun simctl list devices available | grep "$NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun simctl create "$NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max)
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a /Applications/Xcode.app/Contents/Applications/DeviceHub.app   # Xcode 27: the Simulator app is now Device Hub
xcodegen generate --quiet
echo "› Building for $NAME…"
xcodebuild -project DayLive.xcodeproj -scheme DayLive -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build/sim \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  -quiet build
APP=$(ls -d build/sim/Build/Products/Debug-iphonesimulator/*.app | head -1)
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.prabhu.daylive >/dev/null
echo "✓ Running in the $NAME simulator"
