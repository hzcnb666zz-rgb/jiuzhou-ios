#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIGN_DIR="$(mktemp -d)"
KEYCHAIN="$SIGN_DIR/signing.keychain-db"
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$SIGN_DIR"
}
trap cleanup EXIT
printf '%s' "$IOS_P12_BASE64" | base64 --decode > "$SIGN_DIR/certificate.p12"
printf '%s' "$IOS_PROFILE_BASE64" | base64 --decode > "$SIGN_DIR/profile.mobileprovision"
security cms -D -i "$SIGN_DIR/profile.mobileprovision" > "$SIGN_DIR/profile.plist"
python3 - "$SIGN_DIR/profile.plist" "$SIGN_DIR/entitlements.plist" <<'PY'
import datetime, plistlib, sys
with open(sys.argv[1], 'rb') as f:
    profile = plistlib.load(f)
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Provisioning profile expired'
assert profile.get('ProvisionedDevices'), 'No provisioned devices'
assert profile['Entitlements']['application-identifier'].endswith('.app.vanilla7419.emerald5335'), 'Bundle ID mismatch'
with open(sys.argv[2], 'wb') as f:
    plistlib.dump(profile['Entitlements'], f)
print('Profile validated; registered devices:', len(profile['ProvisionedDevices']))
PY
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$SIGN_DIR/certificate.p12" -k "$KEYCHAIN" -P "$IOS_P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/[0-9A-F]{40}/ {print $2; exit}')"
test -n "$IDENTITY"
APP="build/package/Payload/Jiuzhou.app"
cp "$SIGN_DIR/profile.mobileprovision" "$APP/embedded.mobileprovision"
if [ -d "$APP/Frameworks" ]; then
  while IFS= read -r -d '' item; do
    codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --timestamp=none "$item"
  done < <(find "$APP/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
fi
codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --entitlements "$SIGN_DIR/entitlements.plist" --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" > "$SIGN_DIR/signed-entitlements.plist"
python3 - "$APP/Info.plist" "$SIGN_DIR/signed-entitlements.plist" "$SIGN_DIR/profile.plist" <<'PY'
import plistlib, sys
info, signed, profile = [plistlib.load(open(p, 'rb')) for p in sys.argv[1:]]
assert signed['application-identifier'] == profile['Entitlements']['application-identifier']
assert signed['application-identifier'].endswith('.' + info['CFBundleIdentifier'])
print('Signed app bundle ID and entitlements verified')
PY
(cd build/package && /usr/bin/zip -qry ../Jiuzhou-signed.ipa Payload)
shasum -a 256 build/Jiuzhou-signed.ipa
