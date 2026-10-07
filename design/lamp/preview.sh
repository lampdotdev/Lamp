#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

APP="build/OnboardingPreview.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc Sources/Lamp/LampBackdrop.swift design/lamp/PlaybackHarness.swift -o "$APP/Contents/MacOS/OnboardingPreview"
cp design/lamp/Preview-Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Onboarding"
cp Resources/Onboarding/* "$APP/Contents/Resources/Onboarding/"
"$APP/Contents/MacOS/OnboardingPreview" "$@"
