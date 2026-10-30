#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/validation
chmod +x Tests/fixture_codex.py
for pass in 1 2; do
  zsh build.sh 2>&1 | tee ".build/validation/build-$pass.log"
  dist/DockGrove.app/Contents/MacOS/DockGrove --self-test --fixture-cli "$PWD/Tests/fixture_codex.py" 2>&1 | tee ".build/validation/tests-$pass.log"
  codesign --verify --strict dist/DockGrove.app
  plutil -lint dist/DockGrove.app/Contents/Info.plist
  lipo dist/DockGrove.app/Contents/MacOS/DockGrove -verify_arch arm64
  lipo dist/DockGrove.app/Contents/MacOS/DockGrove -verify_arch x86_64
  if (( ${@[(Ie)--native]} )); then
    dist/DockGrove.app/Contents/MacOS/DockGrove --native-test "$PWD/.build/validation/native-$pass" 2>&1 | tee ".build/validation/native-$pass.log"
  fi
  if (( ${@[(Ie)--live]} )); then
    dist/DockGrove.app/Contents/MacOS/DockGrove --live-test 2>&1 | tee ".build/validation/live-$pass.log"
  fi
done
