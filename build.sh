#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mode="${1:---development}"
if [[ "$mode" != "--development" && "$mode" != "--commercial" && "$mode" != "--commercial-qa" ]]; then
  echo "Usage: build.sh [--development|--commercial|--commercial-qa]" >&2; exit 2
fi
flags=()
bundle="dist/WaveDock.app"
if [[ "$mode" == "--commercial" || "$mode" == "--commercial-qa" ]]; then
  flags=(-D WAVEDOCK_COMMERCIAL)
  bundle="dist/WaveDock-Commercial.app"
fi
if [[ "$mode" == "--commercial-qa" ]]; then bundle="dist/WaveDock-Commercial-QA.app"; fi
mkdir -p .build/cache "$bundle/Contents/MacOS"
if [[ "$mode" == "--commercial" ]]; then
  xcrun swiftc -module-cache-path .build/cache Scripts/ValidateLicenseConfig.swift -o .build/validate-license-config
  .build/validate-license-config
fi
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O "${flags[@]}" \
    -target "$arch-apple-macosx14.0" -module-cache-path .build/cache \
    -framework AppKit -framework SwiftUI -framework Combine -framework EventKit -framework IOKit -framework ServiceManagement -framework ApplicationServices -framework Security -framework CoreAudio -framework AVFoundation \
    Sources/*.swift -o ".build/WaveDock-$arch"
done
lipo -create .build/WaveDock-arm64 .build/WaveDock-x86_64 -output "$bundle"/Contents/MacOS/WaveDock
cp Info.plist "$bundle"/Contents/Info.plist
python3 - "$bundle/Contents/Info.plist" "$mode" <<'PYCONFIG'
import os, plistlib, sys
path, mode = sys.argv[1:]
with open(path, 'rb') as f: info = plistlib.load(f)
if mode == '--development':
    info['CFBundleIdentifier'] = 'com.dylan.wavedock.development'
    info['CFBundleDisplayName'] = 'WaveDock Development'
if mode == '--commercial-qa':
    info['CFBundleIdentifier'] = 'com.dylan.wavedock.commercial-qa'
    info['CFBundleDisplayName'] = 'WaveDock Commercial QA'
for key, variable in [('WaveDockLicenseServerURL','WAVEDOCK_LICENSE_SERVER_URL'), ('WaveDockLicensePublicKeyBase64','WAVEDOCK_LICENSE_PUBLIC_KEY'), ('WaveDockLicenseKeyID','WAVEDOCK_LICENSE_KEY_ID')]:
    if os.environ.get(variable): info[key] = os.environ[variable]
with open(path, 'wb') as f: plistlib.dump(info, f)
PYCONFIG
mkdir -p "$bundle"/Contents/Resources/Companions
# The bundle is generated output; remove stale artwork from previous local builds.
rm -f "$bundle"/Contents/Resources/Companions/*.png(N)
cp Assets/Companions/*.png "$bundle"/Contents/Resources/Companions/
xcrun swiftc -module-cache-path .build/cache -framework AppKit Scripts/MakeIcon.swift -o .build/make-icon
.build/make-icon .build/WaveDock.iconset "$bundle"/Contents/Resources/WaveDock.icns
codesign --force --sign - "$bundle"
echo "Built $bundle ($mode, Apple Silicon + Intel, macOS 14+)"
