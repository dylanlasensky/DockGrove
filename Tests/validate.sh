#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/validation
chmod +x Tests/fixture_codex.py
for pass in 1 2; do
  zsh build.sh 2>&1 | tee ".build/validation/build-$pass.log"
  dist/WaveDock.app/Contents/MacOS/WaveDock --self-test --fixture-cli "$PWD/Tests/fixture_codex.py" 2>&1 | tee ".build/validation/tests-$pass.log"
  codesign --verify --strict dist/WaveDock.app
  plutil -lint dist/WaveDock.app/Contents/Info.plist
  lipo -verify_arch arm64 dist/WaveDock.app/Contents/MacOS/WaveDock
  lipo -verify_arch x86_64 dist/WaveDock.app/Contents/MacOS/WaveDock
  if (( ${@[(Ie)--native]} )); then
    dist/WaveDock.app/Contents/MacOS/WaveDock --native-test "$PWD/.build/validation/native-$pass" 2>&1 | tee ".build/validation/native-$pass.log"
  fi
  if (( ${@[(Ie)--live]} )); then
    dist/WaveDock.app/Contents/MacOS/WaveDock --live-test 2>&1 | tee ".build/validation/live-$pass.log"
  fi
done
