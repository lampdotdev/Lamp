#!/bin/zsh
# Seeds the development build (Lamp Dev) from the Lamp you use: copies your apps, keys, settings and the
# agent's sign-ins, so Lamp Dev starts with something to work on instead of the welcome screen.
#
#   scripts/dev-data.sh          copy what Lamp Dev doesn't have yet
#   scripts/dev-data.sh --all    also replace what it does have (apps with the same name, keys, settings)
#
# Everything is copied, never moved: the installed Lamp isn't touched. Lamp Dev rebuilds each copied app
# the first time it opens it (the dev build's apps have their own bundle ids, so they sit beside the
# originals). The built apps in ~/Applications/Lamp Apps aren't copied for that reason, and neither are
# downloaded models, which both Lamps find in the shared Hugging Face cache.
set -euo pipefail

replace=0
[ "${1:-}" = --all ] && replace=1
support="$HOME/Library/Application Support"
from="$support/Lamp"; to="$support/Lamp Dev"
from_domain="dev.lamp.host"; to_domain="dev.lamp.host.dev"

[ -d "$from" ] || { echo "Nothing to copy: no $from." >&2; exit 1; }
osascript -e 'quit app "Lamp Dev"' >/dev/null 2>&1 || true
sleep 1
mkdir -p "$to/Apps"

# Apps: the project folders, chats and versions included.
copied=0
for app in "$from"/Apps/*(N/); do
  name="${app:t}"
  if [ -d "$to/Apps/$name" ]; then
    [ $replace = 1 ] || { echo "kept    $name (already in Lamp Dev)"; continue }
    rm -rf "$to/Apps/$name"
  fi
  cp -R "$app" "$to/Apps/$name"
  # Built from the installed Lamp: Lamp Dev builds it again, for its own bundle id and gateway.
  rm -f "$to/Apps/$name/.lamp/runtime/built"
  # The app's own saved data, under its dev bundle id, so it opens where it left off.
  if [ -d "$support/dev.lamp.app.$name" ] && { [ $replace = 1 ] || [ ! -d "$support/dev.lamp.dev.app.$name" ]; }; then
    rm -rf "$support/dev.lamp.dev.app.$name"
    cp -R "$support/dev.lamp.app.$name" "$support/dev.lamp.dev.app.$name"
  fi
  echo "copied  $name"
  copied=$((copied + 1))
done

# Keys and the agent's config (pi's sign-ins and settings).
for item in keys.json pi; do
  [ -e "$from/$item" ] || continue
  if [ -e "$to/$item" ] && [ $replace = 0 ]; then echo "kept    $item"; continue; fi
  rm -rf "$to/$item"; cp -R "$from/$item" "$to/$item"; echo "copied  $item"
done

# Keychain items (keys of a signed build): read each from Lamp's service, add under Lamp Dev's.
security dump-keychain 2>/dev/null | awk -v svc="\"$from_domain\"" '
  /"acct"<blob>=/ { acct = $0; sub(/.*"acct"<blob>="/, "", acct); sub(/"$/, "", acct) }
  /"svce"<blob>=/ { svce = $0; sub(/.*"svce"<blob>=/, "", svce); if (svce == svc) print acct }' |
while read -r account; do
  [ -n "$account" ] || continue
  if [ $replace = 0 ] && security find-generic-password -s "$to_domain" -a "$account" >/dev/null 2>&1; then
    echo "kept    key for $account"; continue
  fi
  secret="$(security find-generic-password -s "$from_domain" -a "$account" -w 2>/dev/null)" || continue
  security add-generic-password -s "$to_domain" -a "$account" -w "$secret" -U >/dev/null && echo "copied  key for $account"
done

# Settings (which agent, models, approvals, privacy).
if [ $replace = 1 ] || ! defaults read "$to_domain" >/dev/null 2>&1; then
  plist="$(mktemp)"; defaults export "$from_domain" "$plist" 2>/dev/null && [ -s "$plist" ] && {
    defaults delete "$to_domain" >/dev/null 2>&1 || true
    defaults import "$to_domain" "$plist" && echo "copied  settings"
  }
  rm -f "$plist"
else
  echo "kept    settings"
fi

echo "Done: $copied app(s) copied. Open build/Lamp Dev.app."
