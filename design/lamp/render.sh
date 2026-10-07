#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

BLENDER_BIN="${BLENDER_BIN:-/Applications/Blender.app/Contents/MacOS/Blender}"
test -x "$BLENDER_BIN" || { echo "Install Blender or set BLENDER_BIN to its executable." >&2; exit 1; }
command -v ffmpeg >/dev/null
mkdir -p build/onboarding
swiftc design/lamp/SceneKitBackdrop.swift design/lamp/export-model.swift -o build/onboarding/export-model
build/onboarding/export-model build/onboarding/lamp.obj
"$BLENDER_BIN" --background --factory-startup --python design/lamp/render-onboarding.py -- \
  --model build/onboarding/lamp.obj --output build/onboarding/final --frames all
python3 design/lamp/encode-onboarding.py build/onboarding/final Resources/Onboarding
