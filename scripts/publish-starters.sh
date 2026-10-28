#!/bin/zsh
# Refreshes what's Lamp's in each starter's repository on GitHub (<account>/<folder>, the account as `Starters.account`
# names it; a public repository each, made here when missing): Lamp's own files so `./build.sh` builds it, the README,
# license and pictures, the description, and a game's page on the gh-pages branch, served by GitHub Pages at
# <account>.github.io/<folder>. It writes the repository's address and the commit it's at into the starter's starter.md
# (`repository:` and `commit:`): every copy of a starter made by a Lamp built from then on names that commit on its
# chain, which Update from GitHub… merges against and Send Changes Back… goes on top of.
#
# The repository is where the starter is made; Resources/Starters is Lamp's copy of it (scripts/pull-starters.sh). So
# this never puts the app itself up: a starter whose copy here differs from its repository in the app (its code, files,
# notes, credits) is refused, with what to do (pull it, or send the change to the repository first).
#
# Run it before a release, after pulling, and commit the starter.md files it touches:
#   ./build.sh && scripts/pull-starters.sh && scripts/publish-starters.sh            every starter
#   scripts/publish-starters.sh newyork hours                                          some, by folder name
# A starter whose tree is the same as what's up makes no commit. Needs gh, signed in to an account that can push to
# those repositories. `--dry-run` stages the trees and says what it would do, without GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0
failed=0
[[ "${1:-}" == "--dry-run" ]] && { DRY=1; shift; }
only=("$@")
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
  if (( $#only )) && [[ ${only[(Ie)$folder]} -eq 0 ]]; then continue; fi
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
  # The starter as it is now in place of what's there: one commit of the difference, or none. The app itself is the
  # repository's to change: a difference there (anything but what Lamp writes, listed by the staging) stops this one.
  find "$clone" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  cp -R "$tree"/. "$clone"/
  cd "$clone"
  "$GIT" add -A
  excluded=()
  while IFS= read -r derived; do [[ -n "$derived" ]] && excluded+=(":(exclude)$derived"); done < "$tree.derived"
  if "$GIT" rev-parse -q --verify HEAD >/dev/null && ! "$GIT" diff --cached --quiet -- . "${excluded[@]}"; then
    echo "$repo: the app differs from the repository's, which is where it's made:" >&2
    "$GIT" diff --cached --stat -- . "${excluded[@]}" | sed 's/^/    /' >&2
    echo "    Pull it (scripts/pull-starters.sh $folder) or send the change to the repository first (Send Changes Back… from Lamp, or a push there)." >&2
    cd "$OLDPWD"
    failed=1
    continue
  fi
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
        # A push that fails stops the script with what git said; GitHub's chatter about a new branch is left out.
        if ! said="$("$GIT" -c credential.helper= -c "credential.helper=!gh auth git-credential" push -q "https://github.com/$repo.git" HEAD:gh-pages 2>&1)"; then
          print -u2 -r -- "$said"
          exit 1
        fi
        print -r -- "$said" | grep -v '^remote:' || true
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
  /usr/bin/python3 scripts/starter-commit.py "$starter" "https://github.com/$repo" "$sha"
done
(( failed )) && exit 1
(( DRY )) || echo "Commit the starter.md files that changed (git status Resources/Starters)."
