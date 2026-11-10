#!/bin/zsh
# lamp, as Lamp's app carries it (Lamp.app/Contents/Resources/cli/lamp): run on the runtime the app already has, pi,
# which is Bun when BUN_BE_BUN is set, so a Mac with Lamp needs no Node of its own. It fetches nothing and reads no
# .env file, as Lamp's own calls of it don't (LampCLI.swift).
here="${0:A:h}"
export BUN_BE_BUN=1 LAMP_FROM_APP=1
# The Lamp it reaches (`lamp open --in-lamp`, outside.mjs) is the one it ships in, Nightly and Dev included, unless
# LAMP_APP names another.
if [[ -z "${LAMP_APP:-}" ]]; then
  bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$here/../../Info.plist" 2>/dev/null || true)"
  [[ -n "$bundle" ]] && export LAMP_APP="$bundle"
fi
exec "$here/../pi/pi" --no-install --no-env-file "$here/lamp.mjs" "$@"
