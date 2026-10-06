#!/bin/zsh
# Try Forge's first run on this Mac without losing your setup.
#
#   scripts/fresh-start.sh begin     quit Forge, put its state aside, open it as a first-time user would
#   scripts/fresh-start.sh restore   quit Forge, put your state back
#
# Forge keeps everything in three places: ~/Library/Application Support/Forge (apps, keys.json, pi's config,
# the signing keychain, downloaded models), the defaults domain dev.forge.host (engine, provider, models,
# privacy switches, Sparkle's update state) and, for notarized builds, Keychain items with service
# dev.forge.host (provider keys). `begin` moves the folder, exports the defaults and copies the Keychain
# items into one backup folder, and `restore` puts them all back. Nothing is deleted until you restore.
#
# This covers the welcome screen, the key check, picking an engine, and making the first app. It can't
# show a Mac without the Command Line Tools, Gatekeeper on a fresh download, or the permission prompts
# you've already answered: for those, use a second macOS user (permissions) or a clean VM (everything).
set -euo pipefail

support="$HOME/Library/Application Support"
state="$support/Forge"
backup="$support/Forge-fresh-start"
domain="dev.forge.host"

# The accounts of every Keychain item with Forge's service name, one per line.
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
  osascript -e 'quit app "Forge"' >/dev/null 2>&1 || true
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
  # A Mac that never ran Forge has no folder: remember that, so restore can take the fresh one away.
  if [ -e "$state" ]; then mv "$state" "$backup/Forge"; else touch "$backup/no-folder"; fi
  defaults export "$domain" "$backup/defaults.plist" 2>/dev/null || true
  defaults delete "$domain" >/dev/null 2>&1 || true
  keychain_accounts | while read -r account; do
    security delete-generic-password -s "$domain" -a "$account" >/dev/null 2>&1 || true
  done
  echo "Your Forge setup is in $backup. Opening Forge as a first-time user."
  echo "When you're done: scripts/fresh-start.sh restore"
  open -a Forge 2>/dev/null || open "$(dirname "$0")/../build/Forge.app"
}

restore() {
  if [ ! -d "$backup" ]; then
    echo "Nothing to restore: no $backup." >&2
    exit 1
  fi
  osascript -e 'quit app "Forge"' >/dev/null 2>&1 || true
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
  # Whatever the fresh run made is thrown away; your apps come back. Only when the backup still holds
  # them (or says there were none), so running this twice can't remove a folder that was already restored.
  if [ -e "$backup/Forge" ]; then
    rm -rf "$state"
    mv "$backup/Forge" "$state"
  elif [ -e "$backup/no-folder" ]; then
    rm -rf "$state"
    rm -f "$backup/no-folder"
  fi
  rm -rf "$backup"
  echo "Your Forge setup is back."
}

case "${1:-}" in
  begin) begin ;;
  restore) restore ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
