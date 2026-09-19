#!/bin/bash
set -euo pipefail
mkdir -p build/screenshots
xcrun simctl list devices available -j > build/devices.json
python3 - <<'PY' > build/screenshot-devices.txt
import json
devices = json.load(open('build/devices.json'))['devices']
for prefix in ('iPhone', 'iPad'):
    matches = [d for runtime, rows in devices.items() if 'iOS' in runtime for d in rows if d['name'].startswith(prefix)]
    if not matches:
        raise SystemExit('Missing simulator: ' + prefix)
    print(prefix + ' ' + matches[0]['udid'])
PY
while read -r family device; do
  xcrun simctl boot "$device" || true
  xcrun simctl bootstatus "$device" -b
  xcrun simctl install "$device" build/simulator/Build/Products/Debug-iphonesimulator/Jiuzhou.app
  xcrun simctl launch --terminate-running-process "$device" app.vanilla7419.emerald5335
  sleep 3
  xcrun simctl io "$device" screenshot "build/screenshots/$family-login.png"
  xcrun simctl launch --terminate-running-process "$device" app.vanilla7419.emerald5335 --ui-check-world
  sleep 3
  xcrun simctl io "$device" screenshot "build/screenshots/$family-world.png"
  for scene in menu dialog input history confirmation; do
    xcrun simctl launch --terminate-running-process "$device" app.vanilla7419.emerald5335 --ui-check-world "--ui-check-$scene"
    sleep 3
    xcrun simctl io "$device" screenshot "build/screenshots/$family-$scene.png"
  done
  if [ "$family" = iPhone ]; then
    xcodebuild -project Jiuzhou.xcodeproj -scheme Jiuzhou -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/simulator -resultBundlePath build/InteractionTests.xcresult test CODE_SIGNING_ALLOWED=NO
  fi
  xcrun simctl shutdown "$device"
done < build/screenshot-devices.txt
