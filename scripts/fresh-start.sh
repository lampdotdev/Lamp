#!/bin/zsh
# Try Lamp's first run on this Mac without losing your setup.
#
#   scripts/fresh-start.sh begin     quit Lamp Dev, put its state aside, open it as a first-time user would
#   scripts/fresh-start.sh restore   quit Lamp Dev, put your state back
#
# It works on the development build (Lamp Dev) unless EDITION=release is given, which sets aside the
# installed Lamp's state instead: the one you use is the one you least want reset by accident.
#
# Lamp keeps everything in three places: ~/Library/Application Support/Lamp (apps, keys.json, pi's config,
# the signing keychain, downloaded models), the defaults domain dev.lamp.host (engine, provider, models,
# privacy switches, Sparkle's update state) and, for notarized builds, Keychain items with service
# dev.lamp.host (provider keys). `begin` moves the folder, exports the defaults and copies the Keychain
# items into one backup folder, and `restore` puts them all back. Nothing is deleted until you restore.
#
# This covers the welcome screen, the key check, picking an engine, and making the first app. Set
# LAMP_PRETEND_MISSING (see Pretend.swift) to also see it as a Mac without the Command Line Tools, Xcode,
# Claude Code, Codex or tools like uv would: LAMP_PRETEND_MISSING=bare scripts/fresh-start.sh begin. It can't
# show Gatekeeper on a fresh download, Apple's own installer, or the permission prompts you've already
# answered: for those, use a second macOS user (permissions) or a clean VM (everything).
set -euo pipefail

# The checkout this script is in, taken here: inside a function zsh gives $0 the function's name.
here="${0:A:h}/.."
support="$HOME/Library/Application Support"
if [ "${EDITION:-dev}" = release ]; then name="Lamp"; domain="dev.lamp.host"; else name="Lamp Dev"; domain="dev.lamp.host.dev"; fi
state="$support/$name"
backup="$support/$name-fresh-start"

# The accounts of every Keychain item with Lamp's service name, one per line.
keychain_accounts() {
  security dump-keychain 2>/dev/null | awk -v svc="\"$domain\"" '
    /"acct"<blob>=/ { acct = $0; sub(/.*"acct"<blob>="/, "", acct); sub(/"$/, "", acct) }
    /"svce"<blob>=/ { svce = $0; sub(/.*"svce"<blob>=/, "", svce); if (svce == svc) print acct }'
}

begin() {
  if [ -e "$backup" ]; then
    echo "A fresh start is already in progress ($backup). Run 'restore' first." >&2
    exit 1
  fi
  osascript -e "quit app \"$name\"" >/dev/null 2>&1 || true
  sleep 1
  mkdir -p "$backup"
  chmod 700 "$backup"
  # Keychain items can't be moved, so copy each one's account and secret into a file only you can read.
  # Every secret is read before anything is touched: if one can't be (the access prompt was denied),
  # nothing has changed yet and the item is still there.
  : > "$backup/keychain.txt"
  chmod 600 "$backup/keychain.txt"
  keychain_accounts | while read -r account; do
    if ! secret="$(security find-generic-password -s "$domain" -a "$account" -w 2>/dev/null)"; then
      echo "Couldn't read the Keychain item for '$account', so nothing was changed. Allow access and try again." >&2
      rm -rf "$backup"
      exit 1
    fi
    printf '%s\t%s\n' "$account" "$secret" >> "$backup/keychain.txt"
  done
  [ -d "$backup" ] || exit 1   # the loop runs in a subshell; it removed the backup on failure
  # A Mac that never ran Lamp has no folder: remember that, so restore can take the fresh one away.
  if [ -e "$state" ]; then mv "$state" "$backup/Lamp"; else touch "$backup/no-folder"; fi
  defaults export "$domain" "$backup/defaults.plist" 2>/dev/null || true
  defaults delete "$domain" >/dev/null 2>&1 || true
  # Settings from before the rename would be migrated back in on the next launch: set them aside too.
  if [ "$name" = Lamp ]; then   # release only: the Forge-era settings never applied to a dev build
    defaults export dev.forge.host "$backup/defaults-forge.plist" 2>/dev/null || true
    defaults delete dev.forge.host >/dev/null 2>&1 || true
  fi
  keychain_accounts | while read -r account; do
    security delete-generic-password -s "$domain" -a "$account" >/dev/null 2>&1 || true
  done
  echo "Your $name setup is in $backup. Opening $name as a first-time user."
  echo "When you're done: scripts/fresh-start.sh restore"
  # Passed on only when set, so a plain begin opens Lamp as it always did.
  local env=()
  [ -n "${LAMP_PRETEND_MISSING:-}" ] && env=(--env "LAMP_PRETEND_MISSING=$LAMP_PRETEND_MISSING")
  # Lamp Dev is this checkout's own build when there is one: by name, macOS picks whichever copy it likes, and
  # every worktree that ever built Lamp Dev has one, however old.
  local own="$here/build/$name.app"
  if [ "$name" = "Lamp Dev" ] && [ -d "$own" ]; then
    open "${env[@]}" "$own"
  else
    open "${env[@]}" -a "$name" 2>/dev/null || open "${env[@]}" "$own"
  fi
}

restore() {
  # A backup made before the rename holds the folder under its old name.
  if [ "$name" = Lamp ] && [ ! -d "$backup" ] && [ -d "$support/Forge-fresh-start" ]; then   # release only: Forge was never dev
    mv "$support/Forge-fresh-start" "$backup"
    [ -e "$backup/Forge" ] && mv "$backup/Forge" "$backup/Lamp"
  fi
  if [ ! -d "$backup" ]; then
    echo "Nothing to restore: no $backup." >&2
    exit 1
  fi
  osascript -e "quit app \"$name\"" >/dev/null 2>&1 || true
  sleep 1
  # The steps that can fail come first, while the backup is untouched, so a failed restore can simply be
  # run again. Whatever the fresh run saved in the Keychain goes, then the original items come back.
  keychain_accounts | while read -r account; do
    security delete-generic-password -s "$domain" -a "$account" >/dev/null 2>&1 || true
  done
  while IFS=$'\t' read -r account secret; do
    [ -n "$account" ] || continue
    security add-generic-password -s "$domain" -a "$account" -w "$secret" -U >/dev/null
  done < "$backup/keychain.txt"
  defaults delete "$domain" >/dev/null 2>&1 || true
  if [ -s "$backup/defaults.plist" ]; then defaults import "$domain" "$backup/defaults.plist"; fi
  if [ "$name" = Lamp ] && [ -s "$backup/defaults-forge.plist" ]; then defaults import dev.forge.host "$backup/defaults-forge.plist"; fi
  # Whatever the fresh run made is thrown away; your apps come back. Only when the backup still holds
  # them (or says there were none), so running this twice can't remove a folder that was already restored.
  if [ -e "$backup/Lamp" ]; then
    rm -rf "$state"
    mv "$backup/Lamp" "$state"
  elif [ -e "$backup/no-folder" ]; then
    rm -rf "$state"
    rm -f "$backup/no-folder"
  fi
  rm -rf "$backup"
  echo "Your $name setup is back."
}

case "${1:-}" in
  begin) begin ;;
  restore) restore ;;
  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
