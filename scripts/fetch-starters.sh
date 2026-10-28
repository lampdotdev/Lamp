#!/bin/zsh
# Fetches each starter's repository at the commit Lamp pins (Resources/Starters/<folder>/starter.md: `repository:` and
# `commit:`) into Resources/Starters/<folder>/tree, which the build bundles and the tests read; never committed here.
# A tree already at its commit is left alone. build.sh runs it first; run it by hand before `swift test`.
#   scripts/fetch-starters.sh            every starter
#   scripts/fetch-starters.sh newyork    one, by folder name
set -euo pipefail
cd "$(dirname "$0")/.."

folders=("$@")
(( $#folders )) || folders=(Resources/Starters/*(N/:t))
failed=0
for folder in "${folders[@]}"; do
  starter="Resources/Starters/$folder/starter.md"
  [[ -f "$starter" ]] || { echo "$folder: no starter.md" >&2; failed=1; continue; }
  url="$(sed -n 's/^repository: *//p' "$starter" | head -1)"
  sha="$(sed -n 's/^commit: *//p' "$starter" | head -1)"
  [[ -n "$url" && -n "$sha" ]] || { echo "$folder: starter.md names no repository and commit" >&2; failed=1; continue; }
  tree="Resources/Starters/$folder/tree"
  if [[ -d "$tree/.git" ]] && [[ "$(git -C "$tree" rev-parse HEAD 2>/dev/null)" == "$sha" ]]; then continue; fi
  rm -rf "$tree"
  mkdir -p "$tree"
  if ! ( cd "$tree" && git init -q && git remote add origin "${url%/}.git" \
         && GIT_TERMINAL_PROMPT=0 git fetch -q --depth 1 origin "$sha" && git checkout -q --detach FETCH_HEAD ); then
    echo "$folder: couldn't fetch $url at ${sha:0:7}" >&2
    rm -rf "$tree"
    failed=1
    continue
  fi
  echo "$folder: ${sha:0:7}"
done
exit $failed
