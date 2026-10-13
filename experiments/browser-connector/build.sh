#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
SIGN_IDENTITY=- ./build.sh
APP="build/Lamp Dev.app"
mkdir -p "$APP/Contents/Helpers"
xcrun swiftc -O -target arm64-apple-macos14 experiments/browser-connector/NativeHost.swift -o "$APP/Contents/Helpers/BrowserNativeHost"
codesign --force -s - "$APP/Contents/Helpers/BrowserNativeHost"
codesign --force -s - "$APP"
