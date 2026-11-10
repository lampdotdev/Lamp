#!/bin/zsh
# lamp, as Lamp's app carries it (Lamp.app/Contents/Resources/cli/lamp): run on the runtime the app already has, pi,
# which is Bun when BUN_BE_BUN is set, so a Mac with Lamp needs no Node of its own. It fetches nothing and reads no
# .env file, as Lamp's own calls of it don't (LampCLI.swift).
here="${0:A:h}"
export BUN_BE_BUN=1 LAMP_FROM_APP=1
exec "$here/../pi/pi" --no-install --no-env-file "$here/lamp.mjs" "$@"
