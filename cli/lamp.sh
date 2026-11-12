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
# A newer lamp fetched from npm (update.mjs) runs in this one's place, while it's newer than this app's: ~/.lamp/cli/use
# names it, with the app version it was fetched for, so an app that has updated since runs its own again.
script="$here/lamp.mjs"
bundled="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$here/package.json" 2>/dev/null | head -1)"
export LAMP_LAUNCHER=1 LAMP_BUNDLED_VERSION="$bundled"
use="${LAMP_DEV_HOME:+${LAMP_DEV_HOME:h}}"; use="${use:-$HOME/.lamp}/cli/use"
if [[ -z "${LAMP_NO_UPDATE_CHECK:-}" && -n "$bundled" && -r "$use" ]]; then
  lines=("${(@f)$(<"$use")}")
  [[ "${lines[1]}" == "$bundled" && -f "${lines[2]}/cli/lamp.mjs" ]] && script="${lines[2]}/cli/lamp.mjs"
fi
exec "$here/../pi/pi" --no-install --no-env-file "$script" "$@"
