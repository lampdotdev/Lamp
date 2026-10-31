#!/bin/zsh
# Fetches each starter's repository at the commit Lamp pins (Resources/Starters/<folder>/starter.md: `repository:` and
# `commit:`) into Resources/Starters/<folder>/tree, which the build bundles and the tests read; never committed here.
# A tree already at its commit is left alone, and a starter.md with no pin yet (a starter being made, before
# scripts/publish-starters.sh --new) is passed over, so the build that publishes it can run. build.sh runs it first;
# run it by hand before `swift test`.
#   scripts/fetch-starters.sh            every starter
#   scripts/fetch-starters.sh newyork    one, by folder name
set -euo pipefail
cd "$(dirname "$0")/.."

folders=("$@")
if (( $#folders )); then
  swept=()
else
  folders=(Resources/Starters/*(N/:t))
  # A starter taken out of Lamp leaves its fetched tree (never committed) behind, in a folder with no starter.md and
  # nothing else in it: swept away, so it isn't built into the app. A folder with anything of its own is left, and told of.
  swept=()
  for folder in "${folders[@]}"; do
    dir="Resources/Starters/$folder"
    [[ -f "$dir/starter.md" ]] && continue
    others=("$dir"/*(N) "$dir"/.[^.]*(N))
    if (( $#others == 1 )) && [[ "${others[1]:t}" == tree ]]; then
      echo "$folder: no longer a starter, removing its fetched tree"
      rm -rf "$dir"
      swept+=("$folder")
    fi
  done
  folders=(${folders:|swept})
fi
failed=0
for folder in "${folders[@]}"; do
  starter="Resources/Starters/$folder/starter.md"
  [[ -f "$starter" ]] || { echo "$folder: no starter.md" >&2; failed=1; continue; }
  url="$(sed -n 's/^repository: *//p' "$starter" | head -1)"
  sha="$(sed -n 's/^commit: *//p' "$starter" | head -1)"
  [[ -n "$url" && -n "$sha" ]] || { echo "$folder: not published yet (scripts/publish-starters.sh --new), no tree"; continue; }
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
