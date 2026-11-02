#!/bin/bash
# Builds Soundweaver.app with the Swift compiler from Xcode or the Command Line Tools.
# Usage: ./build.sh            -> build/Soundweaver.app
#        ./build.sh install    -> also copies it to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Note: DDC control in this app only works on Apple silicon Macs." >&2
fi

APP="build/Soundweaver.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit -framework SwiftUI -framework CoreAudio \
  -framework AudioToolbox -framework IOKit -framework ApplicationServices \
  -framework ServiceManagement \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Soundweaver"

cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Soundweaver 2>/dev/null || true
  rm -rf "/Applications/Soundweaver.app"
  cp -R "$APP" /Applications/
  open "/Applications/Soundweaver.app"
  echo "Installed to /Applications and launched."
fi
