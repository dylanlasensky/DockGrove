#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mode="${1:---development}"
if [[ "$mode" != "--development" && "$mode" != "--commercial" && "$mode" != "--commercial-qa" ]]; then
  echo "Usage: build.sh [--development|--commercial|--commercial-qa]" >&2; exit 2
fi
flags=()
bundle="dist/DockGrove.app"
if [[ "$mode" == "--commercial" || "$mode" == "--commercial-qa" ]]; then
  flags=(-D DOCKGROVE_COMMERCIAL)
  bundle="dist/DockGrove-Commercial.app"
fi
if [[ "$mode" == "--commercial-qa" ]]; then bundle="dist/DockGrove-Commercial-QA.app"; fi
mkdir -p .build/cache "$bundle/Contents/MacOS"
if [[ "$mode" == "--commercial" ]]; then
  xcrun swiftc -module-cache-path .build/cache Scripts/ValidateLicenseConfig.swift -o .build/validate-license-config
  .build/validate-license-config
fi
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O "${flags[@]}" \
    -target "$arch-apple-macosx14.0" -module-cache-path .build/cache \
    -framework AppKit -framework SwiftUI -framework Combine -framework EventKit -framework IOKit -framework ServiceManagement -framework ApplicationServices -framework Security -framework CoreAudio -framework AVFoundation \
    Sources/*.swift -o ".build/DockGrove-$arch"
done
lipo -create .build/DockGrove-arm64 .build/DockGrove-x86_64 -output "$bundle"/Contents/MacOS/DockGrove
cp Info.plist "$bundle"/Contents/Info.plist
python3 - "$bundle/Contents/Info.plist" "$mode" <<'PYCONFIG'
import os, plistlib, sys
path, mode = sys.argv[1:]
with open(path, 'rb') as f: info = plistlib.load(f)
if mode == '--development':
    info['CFBundleIdentifier'] = 'com.dylan.wavedock.development'
    info['CFBundleDisplayName'] = 'DockGrove Development'
if mode == '--commercial-qa':
    info['CFBundleIdentifier'] = 'com.dylan.wavedock.commercial-qa'
    info['CFBundleDisplayName'] = 'DockGrove Commercial QA'
for key, variable in [('DockGroveLicenseServerURL','DOCKGROVE_LICENSE_SERVER_URL'), ('DockGroveLicensePublicKeyBase64','DOCKGROVE_LICENSE_PUBLIC_KEY'), ('DockGroveLicenseKeyID','DOCKGROVE_LICENSE_KEY_ID')]:
    if os.environ.get(variable): info[key] = os.environ[variable]
with open(path, 'wb') as f: plistlib.dump(info, f)
PYCONFIG
mkdir -p "$bundle"/Contents/Resources/Companions
# The bundle is generated output; remove stale artwork from previous local builds.
rm -f "$bundle"/Contents/Resources/Companions/*.png(N)
cp Assets/Companions/*.png "$bundle"/Contents/Resources/Companions/
cp Assets/Brand/DockGrove-icon.png "$bundle"/Contents/Resources/
xcrun swiftc -module-cache-path .build/cache -framework AppKit Scripts/MakeIcon.swift -o .build/make-icon
.build/make-icon .build/DockGrove.iconset "$bundle"/Contents/Resources/DockGrove.icns
codesign --force --sign - "$bundle"
echo "Built $bundle ($mode, Apple Silicon + Intel, macOS 14+)"
