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
  # Built from the installed Lamp: Lamp Dev builds it again, for its own bundle id and gateway. The id in
  # the app's build script is rewritten here and committed, so a restored version carries it too (Lamp
  # also puts it right before every build, whichever way the app arrived).
  rm -f "$to/Apps/$name/.lamp/runtime/built"
  [ -f "$to/Apps/$name/build.sh" ] && sed -i '' "s|<string>dev\.lamp\.app\.$name</string>|<string>dev.lamp.dev.app.$name</string>|" "$to/Apps/$name/build.sh"
  [ -f "$to/Apps/$name/build.sh" ] && git -C "$to/Apps/$name" add build.sh >/dev/null 2>&1 && \
    git -C "$to/Apps/$name" -c user.name=Lamp -c user.email=lamp@localhost commit -qm "Lamp Dev's copy" >/dev/null 2>&1 || true
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

# Keys the installed Lamp keeps in the Keychain (a signed build does). Lamp Dev is built without a Team ID
# and reads keys.json instead, so they go into that file: merged, only you can read it, existing entries
# kept unless --all.
keys_file="$to/keys.json"
[ -f "$keys_file" ] || { printf "{}" > "$keys_file"; chmod 600 "$keys_file"; }
security dump-keychain 2>/dev/null | awk -v svc="\"$from_domain\"" '
  /"acct"<blob>=/ { acct = $0; sub(/.*"acct"<blob>="/, "", acct); sub(/"$/, "", acct) }
  /"svce"<blob>=/ { svce = $0; sub(/.*"svce"<blob>=/, "", svce); if (svce == svc) print acct }' |
while read -r account; do
  [ -n "$account" ] || continue
  secret="$(security find-generic-password -s "$from_domain" -a "$account" -w 2>/dev/null)" || continue
  KEYS_FILE="$keys_file" ACCOUNT="$account" SECRET="$secret" REPLACE="$replace" python3 - <<'PY'
import json, os
path = os.environ["KEYS_FILE"]
try:
    keys = json.load(open(path))
except Exception:
    keys = {}
if not isinstance(keys, dict): keys = {}
if os.environ["ACCOUNT"] in keys and os.environ["REPLACE"] == "0":
    print("kept    key for " + os.environ["ACCOUNT"])
else:
    keys[os.environ["ACCOUNT"]] = os.environ["SECRET"]
    with open(path, "w") as f: json.dump(keys, f, indent=2)
    print("copied  key for " + os.environ["ACCOUNT"])
PY
done
chmod 600 "$keys_file"

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
