#!/bin/zsh
# Moves each starter's pin (Resources/Starters/<folder>/starter.md, `commit:`) to its repository's latest commit on
# GitHub, where the starter is made, and fetches the tree (scripts/fetch-starters.sh). Run it before a release, or when
# a starter's repository has moved on, then look at what changed in each tree, run scripts/check-starters.sh and the
# starter tests, and commit the starter.md files it touched.
#   scripts/pull-starters.sh            every starter
#   scripts/pull-starters.sh newyork    some, by folder name
# A starter whose repository is at the pinned commit already is left alone. Needs git; asks GitHub for nothing but the
# repositories' heads.
set -euo pipefail
cd "$(dirname "$0")/.."

folders=("$@")
(( $#folders )) || folders=(Resources/Starters/*(N/:t))
failed=0
moved=()
for folder in "${folders[@]}"; do
  starter="Resources/Starters/$folder/starter.md"
  [[ -f "$starter" ]] || { echo "$folder: no starter.md" >&2; failed=1; continue; }
  url="$(sed -n 's/^repository: *//p' "$starter" | head -1)"
  [[ -n "$url" ]] || { echo "$folder: starter.md names no repository (publish it first: scripts/publish-starters.sh --new)"; continue; }
  known="$(sed -n 's/^commit: *//p' "$starter" | head -1)"
  if ! sha="$(GIT_TERMINAL_PROMPT=0 git ls-remote "${url%/}.git" HEAD 2>/dev/null | awk '{print $1}')" || [[ -z "$sha" ]]; then
    echo "$folder: couldn't ask $url" >&2; failed=1; continue
  fi
  if [[ "$sha" == "$known" ]]; then
    echo "$folder: at ${sha:0:7} already"
    continue
  fi
  /usr/bin/python3 scripts/starter-commit.py "$starter" "$url" "$sha"
  echo "$folder: ${known:0:7} → ${sha:0:7}"
  moved+=("$folder")
done
(( $#moved )) && scripts/fetch-starters.sh "${moved[@]}"
(( failed )) && exit 1
(( $#moved )) && echo "Look at each tree's change (git -C Resources/Starters/<folder>/tree log, or the repository), run scripts/check-starters.sh and swift test --filter StartersTests, then commit the starter.md files."
exit 0
