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
  for scene in register servers account; do
    xcrun simctl launch --terminate-running-process "$device" app.vanilla7419.emerald5335 "--ui-check-$scene"
    sleep 3
    xcrun simctl io "$device" screenshot "build/screenshots/$family-$scene.png"
  done
  xcrun simctl launch --terminate-running-process "$device" app.vanilla7419.emerald5335 --ui-check-world
  sleep 3
  xcrun simctl io "$device" screenshot "build/screenshots/$family-world.png"
  for scene in menu dialog input history confirmation popup map pages common inventory item player npc edge voice; do
    xcrun simctl launch --terminate-running-process "$device" app.vanilla7419.emerald5335 --ui-check-world "--ui-check-$scene"
    sleep 3
    xcrun simctl io "$device" screenshot "build/screenshots/$family-$scene.png"
  done
  xcrun simctl launch --terminate-running-process "$device" app.vanilla7419.emerald5335 --ui-check-world --ui-check-combat
  sleep 1.3
  xcrun simctl io "$device" screenshot "build/screenshots/$family-combat-active.png"
  sleep 2
  xcrun simctl io "$device" screenshot "build/screenshots/$family-combat-finished.png"
  # xcodebuild may already shut down the simulator; cleanup is best-effort.
  xcrun simctl shutdown "$device" || true
done < build/screenshot-devices.txt
test_status=0
while read -r family device; do
  xcodebuild -project Jiuzhou.xcodeproj -scheme Jiuzhou -destination "platform=iOS Simulator,id=$device" -derivedDataPath build/simulator -resultBundlePath "build/InteractionTests-$family.xcresult" test CODE_SIGNING_ALLOWED=NO || test_status=$?
  python3 scripts/export-test-screenshots.py "build/InteractionTests-$family.xcresult" "build/screenshots/attachments-$family"
  xcrun simctl shutdown "$device" || true
done < build/screenshot-devices.txt
exit "$test_status"
