#!/bin/zsh
# Puts each of Lamp's starters on GitHub, a public repository each in the Lamp team's account (RooCodeInc/lamp-starter-
# <folder>), laid out as Put on GitHub lays a wish out, and writes the repository's address and the commit it's at into
# the starter's starter.md (`repository:` and `commit:`). Every copy of a starter made by a Lamp built from then on
# names that commit on its chain, which Update from GitHub… merges against and Send Changes Back… goes on top of.
#
# Run it after a starter changes, before the release that ships the change, and commit the starter.md files it touches:
#   ./build.sh && scripts/publish-starters.sh
# A starter whose tree is the same as what's up makes no commit. Needs gh, signed in to an account that can make
# repositories in RooCodeInc. `--dry-run` stages the trees and says what it would do, without GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1
ACCOUNT="RooCodeInc"

APP=(build/Lamp\ Dev*.app(N/om[1]))
[[ -n "${APP[1]:-}" ]] || { echo "Build Lamp Dev first (./build.sh)." >&2; exit 1; }
BIN="${APP[1]}/Contents/MacOS/${${APP[1]:t}:r}"
GIT=/opt/homebrew/bin/git
[[ -x "$GIT" ]] || GIT=/usr/bin/git

WORK="$(mktemp -d -t lamp-starter-repos)"
trap 'rm -rf "$WORK"' EXIT
STAGE_STARTERS=1 "$BIN" --stage-starter-repos "$WORK/trees"

if (( ! DRY )); then
  gh auth status >/dev/null 2>&1 || { echo "Sign in to GitHub with gh first (gh auth login)." >&2; exit 1; }
  LOGIN="$(gh api user --jq .login)"
fi

for tree in "$WORK"/trees/*(N/); do
  folder="${tree:t}"
  repo="$ACCOUNT/lamp-starter-$folder"
  starter="Resources/Starters/$folder/starter.md"
  if (( DRY )); then
    echo "$repo: $(cd "$tree" && find . -type f | wc -l | tr -d ' ') files"
    continue
  fi
  clone="$WORK/clones/$folder"
  mkdir -p "$clone"
  if gh repo view "$repo" --json name >/dev/null 2>&1; then
    "$GIT" -c credential.helper= -c "credential.helper=!gh auth git-credential" clone -q "https://github.com/$repo.git" "$clone"
  else
    name="$(sed -n 's/^name: *//p' "$starter" | head -1)"
    gh repo create "$repo" --public --description "$name, a starter wish that comes with Lamp" >/dev/null
    (cd "$clone" && "$GIT" init -q -b main)
  fi
  # The starter as it is now in place of what's there: one commit of the difference, or none.
  find "$clone" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  cp -R "$tree"/. "$clone"/
  cd "$clone"
  "$GIT" add -A
  if "$GIT" rev-parse -q --verify HEAD >/dev/null && "$GIT" diff --cached --quiet; then
    echo "$repo: unchanged"
  else
    "$GIT" -c user.name="Lamp" -c user.email="$LOGIN@users.noreply.github.com" commit -q -m "$(sed -n 's/^name: *//p' "$OLDPWD/$starter" | head -1) from Lamp"
    "$GIT" -c credential.helper= -c "credential.helper=!gh auth git-credential" push -q "https://github.com/$repo.git" HEAD:main
    echo "$repo: $("$GIT" rev-parse --short HEAD)"
  fi
  sha="$("$GIT" rev-parse HEAD)"
  cd "$OLDPWD"
  # The address and commit into starter.md's front matter, in place of any there.
  /usr/bin/python3 - "$starter" "https://github.com/$repo" "$sha" <<'PY'
import sys
path, url, sha = sys.argv[1:]
lines = [l for l in open(path).read().split("\n") if not l.startswith(("repository:", "commit:"))]
end = lines.index("---", 1)
at = next((i for i in range(1, end) if lines[i].startswith("tweaks:")), end)
lines[at:at] = [f"repository: {url}", f"commit: {sha}"]
open(path, "w").write("\n".join(lines))
PY
done
(( DRY )) || echo "Commit the starter.md files that changed (git status Resources/Starters)."
