#!/bin/zsh
# Brings Lamp's copy of each starter (Resources/Starters/<folder>, what Lamp ships) up to its repository on GitHub
# (<account>/<folder>, where the starter is made): each repository's main, read as the import reads a repository and
# written in place (scripts/pull-starter.sh for one), with the commit written into the starter's starter.md. Run it
# before a release, or whenever a starter's repository has moved on, and commit what it changed:
#   ./build.sh && scripts/pull-starters.sh            every starter
#   scripts/pull-starters.sh newyork hours            some, by folder name
# A starter whose repository hasn't moved past the commit its starter.md names is left alone. It says when a starter's
# icon design changed (draw its pictures again: desk.md). Needs a Lamp Dev built from this checkout, and git.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=(build/Lamp\ Dev*.app(N/om[1]))
[[ -n "${APP[1]:-}" ]] || { echo "Build Lamp Dev first (./build.sh)." >&2; exit 1; }
BIN="$PWD/${APP[1]}/Contents/MacOS/${${APP[1]:t}:r}"
WORK="$(mktemp -d -t lamp-pull-starters)"
trap 'rm -rf "$WORK"' EXIT

folders=("$@")
(( $#folders )) || folders=(Resources/Starters/*(N/:t))
failed=0
for folder in "${folders[@]}"; do
  starter="Resources/Starters/$folder/starter.md"
  [[ -f "$starter" ]] || { echo "$folder: no such starter" >&2; failed=1; continue; }
  url="$(sed -n 's/^repository: *//p' "$starter" | head -1)"
  [[ -n "$url" ]] || { echo "$folder: no repository named in starter.md (publish it first)"; continue; }
  known="$(sed -n 's/^commit: *//p' "$starter" | head -1)"
  clone="$WORK/$folder"
  if ! GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 "${url%/}.git" "$clone" 2>/dev/null; then
    echo "$folder: couldn't fetch $url" >&2; failed=1; continue
  fi
  sha="$(git -C "$clone" rev-parse HEAD)"
  if [[ "$sha" == "$known" ]]; then
    echo "$folder: at ${sha:0:7} already"
    continue
  fi
  if ! said="$(STAGE_STARTERS=1 "$BIN" --pull-starter "$folder" "$clone" 2>&1)"; then
    print -r -- "$said" >&2; echo "$folder: couldn't be brought in" >&2; failed=1; continue
  fi
  # The copy is now the repository's at this commit; what it says it began from doesn't apply to the copy Lamp ships.
  print -r -- "$said" | grep -v "^Careful: this wish" || true
  /usr/bin/python3 scripts/starter-commit.py "$starter" "$url" "$sha"
  changes="$(git status --short -- "Resources/Starters/$folder" | wc -l | tr -d ' ')"
  echo "$folder: ${known:0:7} → ${sha:0:7}, $changes files changed"
done
(( failed )) && exit 1
echo "Look at the changes (git diff Resources/Starters), run scripts/check-starters.sh and swift test --filter StartersTests, then commit."
