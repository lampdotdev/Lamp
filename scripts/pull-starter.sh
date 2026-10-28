#!/bin/zsh
# Brings a starter changed as a wish in Lamp back into Resources/Starters/<folder>, the starter's source of truth: its
# code and files as the import reads them (never Lamp's own files), APP.md, what it declares, its about.json line and
# what it's based on (credits.json). Its starter.md, preview.png and icon pictures stay as they are. Review the change
# with git, then publish it (scripts/publish-starters.sh). See "Turning an app made with Lamp into a starter" in
# docs/development/desk.md.
#
#   scripts/pull-starter.sh newyork ~/Library/Application\ Support/Lamp\ Dev/Apps/<wish folder>
#   scripts/pull-starter.sh newyork https://github.com/lampdotdev/newyork     (cloned first)
#   scripts/pull-starter.sh --check        every starter, published and brought back, comes back unchanged
#
# Needs a Lamp Dev built from this checkout (./build.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=(build/Lamp\ Dev*.app(N/om[1]))
[[ -n "${APP[1]:-}" ]] || { echo "Build Lamp Dev first (./build.sh)." >&2; exit 1; }
BIN="$PWD/${APP[1]}/Contents/MacOS/${${APP[1]:t}:r}"

if [[ "${1:-}" == "--check" ]]; then
  WORK="$(mktemp -d -t lamp-pull-check)"
  trap 'rm -rf "$WORK"' EXIT
  STAGE_STARTERS=1 "$BIN" --stage-starter-repos "$WORK/trees" >/dev/null
  mkdir -p "$WORK/copy/Resources"
  cp -R Resources/Starters "$WORK/copy/Resources/"
  failed=0
  for tree in "$WORK"/trees/*(N/); do
    folder="${tree:t}"
    # A pull that fails is a failure, not an unchanged starter. A staged tree names no commit (only the repository
    # knows it), which the pull would point out each time: that note is left out.
    if ! said="$(cd "$WORK/copy" && STAGE_STARTERS=1 "$BIN" --pull-starter "$folder" "$tree" 2>&1)"; then
      print -r -- "$said" >&2
      echo "$folder: couldn't be brought back" >&2
      failed=1
      continue
    fi
    print -r -- "$said" | grep -v "^Careful: this wish doesn't say" || true
    if diff -rq -x Prebuilt -x Prebuilt.zip "Resources/Starters/$folder" "$WORK/copy/Resources/Starters/$folder"; then
      echo "$folder: unchanged"
    else
      failed=1
    fi
  done
  exit $failed
fi

[[ $# -eq 2 ]] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
folder="$1"
[[ -f "Resources/Starters/$folder/starter.md" ]] || { echo "No starter named $folder in Resources/Starters." >&2; exit 1; }
source="$2"
# An address is cloned here, one commit deep, with nothing of the person's sent; Lamp reads the clone as it reads any.
if [[ "$source" == https://* || "$source" == github.com/* ]] && [[ ! -e "$source" ]]; then
  CLONE="$(mktemp -d -t lamp-pull-clone)"
  trap 'rm -rf "$CLONE"' EXIT
  GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 "${source%/}.git" "$CLONE/tree" 2>/dev/null \
    || GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 "${source%/}" "$CLONE/tree"
  source="$CLONE/tree"
fi
STAGE_STARTERS=1 "$BIN" --pull-starter "$folder" "$source"
changes="$(git status --short -- "Resources/Starters/$folder")"
if [[ -z "$changes" ]]; then
  echo "$folder: unchanged."
else
  print -r -- "$changes"
  echo "Look at the change (git diff Resources/Starters/$folder), run scripts/check-starters.sh $folder, then publish it."
fi
