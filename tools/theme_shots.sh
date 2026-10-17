#!/bin/zsh
# v55: Today / Stats / Car in light and dark on the simulator (run tools/sim.sh first).
cd "$(dirname "$0")/.."
UDID=687B50B1-F631-4220-B70A-DC258D8957E2
mkdir -p build/theme
for mode in light dark; do
  xcrun simctl ui $UDID appearance $mode
  for tab in today stats car; do
    xcrun simctl terminate $UDID com.prabhu.daylive 2>/dev/null
    xcrun simctl launch $UDID com.prabhu.daylive -hdStartTab $tab >/dev/null
    sleep 6
    xcrun simctl io $UDID screenshot build/theme/$tab-$mode.png >/dev/null 2>&1
  done
done
xcrun simctl ui $UDID appearance light
echo "✓ build/theme"
