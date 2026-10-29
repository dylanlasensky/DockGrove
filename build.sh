#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache dist/WaveDock.app/Contents/MacOS
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O \
    -target "$arch-apple-macosx14.0" -module-cache-path .build/cache \
    -framework AppKit -framework SwiftUI -framework Combine -framework EventKit -framework IOKit -framework ServiceManagement -framework ApplicationServices -framework Security -framework CoreAudio -framework AVFoundation \
    Sources/*.swift -o ".build/WaveDock-$arch"
done
lipo -create .build/WaveDock-arm64 .build/WaveDock-x86_64 -output dist/WaveDock.app/Contents/MacOS/WaveDock
cp Info.plist dist/WaveDock.app/Contents/Info.plist
mkdir -p dist/WaveDock.app/Contents/Resources/Companions
cp Assets/Companions/*.png dist/WaveDock.app/Contents/Resources/Companions/
xcrun swiftc -module-cache-path .build/cache -framework AppKit Scripts/MakeIcon.swift -o .build/make-icon
.build/make-icon .build/WaveDock.iconset dist/WaveDock.app/Contents/Resources/WaveDock.icns
codesign --force --sign - dist/WaveDock.app
echo "Built dist/WaveDock.app (Apple Silicon + Intel, macOS 14+)"
