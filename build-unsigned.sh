#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v xcodebuild >/dev/null; then
  echo 'macOS with Xcode is required. Windows cannot compile an iPhone app.' >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null; then
  echo 'Install XcodeGen first: brew install xcodegen' >&2
  exit 1
fi
swift test
xcodegen generate
xcodebuild -project Jiuzhou.xcodeproj -scheme Jiuzhou -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Jiuzhou.xcodeproj -scheme Jiuzhou -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO build
mkdir -p build/package/Payload
ditto build/device/Build/Products/Release-iphoneos/Jiuzhou.app build/package/Payload/Jiuzhou.app
(cd build/package && /usr/bin/zip -qry ../Jiuzhou-unsigned.ipa Payload)
echo 'Created build/Jiuzhou-unsigned.ipa. It must be signed by a personal sideload tool before installation.'
