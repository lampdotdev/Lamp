#!/bin/zsh
# Puts each of Lamp's starters on GitHub, a public repository each in the Lamp team's account for them (<account>/
# <folder>, the account as `Starters.account` names it), laid out as Put on GitHub lays a wish out, and writes the repository's address and the commit it's at into
# the starter's starter.md (`repository:` and `commit:`). Every copy of a starter made by a Lamp built from then on
# names that commit on its chain, which Update from GitHub… merges against and Send Changes Back… goes on top of.
#
# A game's page goes on the repository's gh-pages branch, served by GitHub Pages at <account>.github.io/<folder>, which its
# README links as "Play it in your browser".
#
# Run it after a starter changes, before the release that ships the change, and commit the starter.md files it touches:
#   ./build.sh && scripts/publish-starters.sh
# A starter whose tree is the same as what's up makes no commit. Needs gh, signed in to an account that can make
# repositories in that account. `--dry-run` stages the trees and says what it would do, without GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1
ACCOUNT="$(sed -n 's/.*static let account = "\(.*\)".*/\1/p' Sources/Lamp/Starters.swift)"

APP=(build/Lamp\ Dev*.app(N/om[1]))
[[ -n "${APP[1]:-}" ]] || { echo "Build Lamp Dev first (./build.sh)." >&2; exit 1; }
BIN="${APP[1]}/Contents/MacOS/${${APP[1]:t}:r}"
GIT=/opt/homebrew/bin/git
[[ -x "$GIT" ]] || GIT=/usr/bin/git

WORK="$(mktemp -d -t lamp-starter-repos)"
trap 'rm -rf "$WORK"' EXIT
STAGE_STARTERS=1 "$BIN" --stage-starter-repos "$WORK/trees" "$WORK/pages"

if (( ! DRY )); then
  gh auth status >/dev/null 2>&1 || { echo "Sign in to GitHub with gh first (gh auth login)." >&2; exit 1; }
  LOGIN="$(gh api user --jq .login)"
fi

for tree in "$WORK"/trees/*(N/); do
  folder="${tree:t}"
  repo="$ACCOUNT/$folder"
  starter="Resources/Starters/$folder/starter.md"
  if (( DRY )); then
    echo "$repo: $(cd "$tree" && find . -type f | wc -l | tr -d ' ') files$([[ -d "$WORK/pages/$folder" ]] && echo ", with its page")"
    continue
  fi
  clone="$WORK/clones/$folder"
  mkdir -p "$clone"
  if gh repo view "$repo" --json name >/dev/null 2>&1; then
    "$GIT" -c credential.helper= -c "credential.helper=!gh auth git-credential" clone -q "https://github.com/$repo.git" "$clone"
  else
    gh repo create "$repo" --public >/dev/null
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
  # What it is, in its own words (about.json), as the repository's description.
  about="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("description",""))' "Resources/Starters/$folder/about.json" 2>/dev/null || true)"
  [[ -n "$about" ]] && gh repo edit "$repo" --description "$about" >/dev/null
  # A game's page: the gh-pages branch, one commit of the difference, served by GitHub Pages.
  if [[ -d "$WORK/pages/$folder" ]]; then
    site="$WORK/sites/$folder"
    mkdir -p "$site"
    (
      cd "$site"
      "$GIT" init -q -b gh-pages
      if "$GIT" -c credential.helper= -c "credential.helper=!gh auth git-credential" fetch -q "https://github.com/$repo.git" gh-pages 2>/dev/null; then
        "$GIT" reset -q --hard FETCH_HEAD
      fi
      find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
      cp -R "$WORK/pages/$folder"/. .
      "$GIT" add -A
      if "$GIT" rev-parse -q --verify HEAD >/dev/null && "$GIT" diff --cached --quiet; then
        echo "$repo page: unchanged"
      else
        "$GIT" -c user.name="Lamp" -c user.email="$LOGIN@users.noreply.github.com" commit -q -m "The page to play"
        "$GIT" -c credential.helper= -c "credential.helper=!gh auth git-credential" push -q "https://github.com/$repo.git" HEAD:gh-pages 2>&1 | grep -v '^remote:' || true
        echo "$repo page: $("$GIT" rev-parse --short HEAD)"
      fi
    )
    page="https://${ACCOUNT:l}.github.io/$folder/"
    # Pushing gh-pages may turn Pages on by itself; turned on already is fine.
    gh api "repos/$repo/pages" >/dev/null 2>&1 \
      || gh api -X POST "repos/$repo/pages" -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null 2>&1 \
      || gh api "repos/$repo/pages" >/dev/null
    gh repo edit "$repo" --homepage "$page" >/dev/null
  fi
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
