#!/bin/zsh
# v52: screenshots of Today, Stats and onboarding at the largest text size + default, on the simulator.
#   zsh tools/a11y_shots.sh      (run tools/sim.sh first so the latest build is installed)
cd "$(dirname "$0")/.."
UDID=687B50B1-F631-4220-B70A-DC258D8957E2
mkdir -p build/a11y
for size in large extra-extra-extra-large; do
  xcrun simctl ui $UDID content_size $size
  for tab in today stats; do
    xcrun simctl terminate $UDID com.prabhu.daylive 2>/dev/null
    xcrun simctl launch $UDID com.prabhu.daylive -hdStartTab $tab >/dev/null
    sleep 4
    xcrun simctl io $UDID screenshot build/a11y/$tab-$size.png >/dev/null 2>&1
  done
done
xcrun simctl ui $UDID content_size large
echo "✓ build/a11y"
