#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/cache .build/DockTestHost.app/Contents/MacOS
xcrun swiftc -module-cache-path .build/cache -framework AppKit Tests/DockTestHost.swift -o .build/DockTestHost.app/Contents/MacOS/DockTestHost
cat > .build/DockTestHost.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.dylan.wavedock.testhost</string><key>CFBundleExecutable</key><string>DockTestHost</string><key>CFBundleName</key><string>DockTestHost</string></dict></plist>
PLIST
open .build/DockTestHost.app
