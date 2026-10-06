#!/bin/zsh
# Build Hyperday and install it on your connected iPhone (cable or same Wi-Fi).
# Usage:  cd ~/Downloads/DayLive && ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

# Your signing team. Regenerating the project wipes the Team picked in Xcode,
# so detect it from your Apple Development certificate (or set DEVELOPMENT_TEAM yourself).
if [[ -z "${DEVELOPMENT_TEAM:-}" && -f .team ]]; then DEVELOPMENT_TEAM=$(<.team); fi
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
fi
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "✗ Couldn't find your signing team. In Xcode: Settings › Accounts › your Apple ID › Personal Team,"
  echo "  then run:  DEVELOPMENT_TEAM=<10-character ID> ./deploy.sh"
  exit 1
fi
echo "$DEVELOPMENT_TEAM" > .team

# Tesla: only the Client ID goes into the app (it's public by design). The secret never does.
TESLA_CLIENT_ID=$(sed -n 's/^TESLA_CLIENT_ID=//p' .tesla-keys/client.env 2>/dev/null | tr -d '\r' || true)
export DEVELOPMENT_TEAM
echo "› Team $DEVELOPMENT_TEAM"

echo "› Generating Xcode project…"
xcodegen generate --quiet

# Entitlements: the app asks for an App Group (widgets) and HealthKit (sleep for Day Close).
# If signing refuses one, fall back and remember it: .no-healthkit, then .no-app-group.
build() {
  xcodebuild -project DayLive.xcodeproj -scheme DayLive -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic TESLA_CLIENT_ID="${TESLA_CLIENT_ID:-}" \
    "$@" -quiet build
}

echo "› Building…"
LOG=$(mktemp)
try_build() {
  build "$@" 2>&1 | tee "$LOG" && return 0
  # A Swift compile error is a code problem, not signing: stop here, never fall back (the
  # compiler's command line mentions HealthKit, which used to trigger the HealthKit fallback).
  if grep -qE '\.swift:[0-9]+:[0-9]+: error:' "$LOG"; then
    echo "✗ Build failed: code error above (nothing changed in signing)."
    rm -f "$LOG"; exit 1
  fi
  return 1
}

if [[ -f .no-app-group || -n "${NO_APP_GROUP:-}" ]]; then
  try_build CODE_SIGN_ENTITLEMENTS= || { rm -f "$LOG"; exit 1; }
elif [[ -f .no-healthkit ]] && ! try_build CODE_SIGN_ENTITLEMENTS=Hyperday.entitlements; then
  if grep -qiE "app group|application-groups|Personal development teams" "$LOG"; then
    echo "› Your Apple ID can't use App Groups. Building without Home Screen widgets…"
    touch .no-app-group
    try_build CODE_SIGN_ENTITLEMENTS= || { rm -f "$LOG"; exit 1; }
  else
    rm -f "$LOG"; exit 1
  fi
elif [[ ! -f .no-healthkit ]] && ! try_build; then
  if grep -qiE "(entitlement|provisioning profile|capabilit).*(healthkit|sign in with apple|applesignin)|(healthkit|applesignin).*(entitlement|provisioning profile|capabilit)" "$LOG"; then
    echo "› Signing refused HealthKit / Sign in with Apple. Building without them…"
    touch .no-healthkit
    if ! try_build CODE_SIGN_ENTITLEMENTS=Hyperday.entitlements; then
      if grep -qiE "app group|application-groups|Personal development teams" "$LOG"; then
        touch .no-app-group
        try_build CODE_SIGN_ENTITLEMENTS= || { rm -f "$LOG"; exit 1; }
      else
        rm -f "$LOG"; exit 1
      fi
    fi
  elif grep -qiE "app group|application-groups|Personal development teams" "$LOG"; then
    echo "› Your Apple ID can't use App Groups. Building without widgets or HealthKit…"
    touch .no-app-group
    try_build CODE_SIGN_ENTITLEMENTS= || { rm -f "$LOG"; exit 1; }
  else
    rm -f "$LOG"; exit 1
  fi
fi
rm -f "$LOG"

APP=build/Build/Products/Debug-iphoneos/DayLive.app

echo "› Finding your iPhone…"
JSON=$(mktemp)
SIMS=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null
xcrun simctl list devices --json > "$SIMS" 2>/dev/null || echo '{"devices":{}}' > "$SIMS"
DEVICE=$(/usr/bin/python3 - "$JSON" "$SIMS" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
# Every Simulator's ID, so a Simulator can never be picked as "your iPhone".
sims = {d["udid"] for group in json.load(open(sys.argv[2])).get("devices", {}).values() for d in group}
def ids(d):
    hp = d.get("hardwareProperties", {})
    return {d.get("identifier"), hp.get("udid")}
phones = [d for d in devices
          if not (ids(d) & sims)
          and d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("connectionProperties", {}).get("pairingState") == "paired"
          and d.get("connectionProperties", {}).get("tunnelState") != "unavailable"]
print(phones[0]["identifier"] if phones else "")
PY
)
rm -f "$JSON" "$SIMS"
if [[ -z "$DEVICE" ]]; then
  echo "✗ No iPhone found. Unlock it and connect by cable or the same Wi-Fi, then try again."
  echo "  Devices Xcode can see:"
  xcrun devicectl list devices 2>/dev/null | sed 's/^/    /' || true
  exit 1
fi

echo "› Installing…"
# Wi-Fi installs can drop mid-transfer ("Connection reset by peer"): try up to 3 times.
for attempt in 1 2 3; do
  if xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null 2>"${TMPDIR:-/tmp}/hd-install.err"; then
    break
  fi
  if [[ $attempt == 3 ]]; then
    cat "${TMPDIR:-/tmp}/hd-install.err"
    echo "✗ Couldn't reach your iPhone. Unlock it, keep it awake on the same Wi-Fi (or plug in the cable), then run ./deploy.sh again."
    exit 1
  fi
  echo "› Connection dropped, retrying ($attempt/3)…"
  sleep 3
done
xcrun devicectl device process launch --device "$DEVICE" com.prabhu.daylive >/dev/null || true
echo "✓ Hyperday is on your iPhone."
