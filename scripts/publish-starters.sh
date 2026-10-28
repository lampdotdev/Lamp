#!/bin/zsh
# Refreshes what's Lamp's in each starter's repository on GitHub (<account>/<folder>, the account `Starters.account`
# names), where the starters are made: Lamp's own files so `./build.sh` builds it, the README, license and pictures,
# the description, and a game's page on the gh-pages branch, served by GitHub Pages at <account>.github.io/<folder>.
# Each repository's latest is cloned and staged as Put on GitHub stages a wish (the app in it stays exactly what the
# repository has: this never puts the app itself up; a repository that can't be fetched stops it, so nothing older
# ever goes up in place of the latest), one commit of the difference goes up (none when there's none),
# and the starter's pin moves to it (Resources/Starters/<folder>/starter.md: `repository:` and `commit:`, with the tree
# fetched). Every copy of a starter made by a Lamp built from then on names that commit on its chain, which Update
# from GitHub… merges against and Send Changes Back… goes on top of.
#
#   ./build.sh && scripts/publish-starters.sh                    every starter
#   scripts/publish-starters.sh newyork hours                    some, by folder name
#   scripts/publish-starters.sh --new <folder> <wish folder>     a new starter: makes its repository from a wish on
#                                                                this Mac (Resources/Starters/<folder>/starter.md first),
#                                                                which the team that makes starters (TEAM) can push to
#   scripts/publish-starters.sh --dry-run [...]                  stages and says what it would do, without GitHub
#
# Run it after changing Lamp's own files, before the release that ships the change; a repository that's the same
# makes no commit. The pictures are the repository's, except ones drawn afresh in the fetched tree since its commit
# (StarterIconsTests draws there; a new preview put there counts too), which go up. Needs gh, signed in to an account
# that can push to those repositories (and make one, for --new).
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=0
NEW=""
WISH=""
[[ "${1:-}" == "--dry-run" ]] && { DRY=1; shift; }
if [[ "${1:-}" == "--new" ]]; then
  [[ $# -ge 3 ]] || { echo "Usage: scripts/publish-starters.sh --new <folder> <wish folder>" >&2; exit 2; }
  NEW="$2"; WISH="$3"; shift 3
  [[ -f "Resources/Starters/$NEW/starter.md" ]] || { echo "Write Resources/Starters/$NEW/starter.md first (desk.md, \"Turning an app made with Lamp into a starter\")." >&2; exit 1; }
fi
only=("$@")
ACCOUNT="$(sed -n 's/.*static let account = "\(.*\)".*/\1/p' Sources/Lamp/Starters.swift)"
# The team in that account whose members push to every starter's repository; a new repository is given to it.
TEAM=starters

APP=(build/Lamp\ Dev*.app(N/om[1]))
[[ -n "${APP[1]:-}" ]] || { echo "Build Lamp Dev first (./build.sh)." >&2; exit 1; }
# A worktree's instance writes its own name into each app's build.sh (its bundle identifiers), which has no place in a
# repository: publish from the main checkout's build.
if [[ "${APP[1]:t}" != "Lamp Dev.app" ]] && (( ! DRY )); then
  echo "${APP[1]:t} is a worktree's instance; publish with the main checkout's Lamp Dev (./build.sh there)." >&2; exit 1
fi
BIN="${APP[1]}/Contents/MacOS/${${APP[1]:t}:r}"
GIT=/opt/homebrew/bin/git
[[ -x "$GIT" ]] || GIT=/usr/bin/git
signed=(-c credential.helper= -c "credential.helper=!gh auth git-credential")

WORK="$(mktemp -d -t lamp-starter-repos)"
trap 'rm -rf "$WORK"' EXIT

if (( ! DRY )); then
  gh auth status >/dev/null 2>&1 || { echo "Sign in to GitHub with gh first (gh auth login)." >&2; exit 1; }
  LOGIN="$(gh api user --jq .login)"
fi

# Each repository's latest, cloned, is what the staging works from: the refresh lands on the repository's main, whatever
# the pin says. Pictures changed in the fetched tree since its commit are drawn afresh, and go over the clone's. A new
# starter has no repository yet: its wish stands in.
mkdir -p "$WORK/latest"
if [[ -n "$NEW" ]]; then
  STAGE_STARTERS=1 "$BIN" --stage-starter-repos "$WORK/trees" "$WORK/pages" --from-wish "$NEW" "$WISH"
else
  for starter in Resources/Starters/*/starter.md(N); do
    folder="${starter:h:t}"
    if (( $#only )) && [[ ${only[(Ie)$folder]} -eq 0 ]]; then continue; fi
    url="$(sed -n 's/^repository: *//p' "$starter" | head -1)"
    [[ -n "$url" ]] || continue
    GIT_TERMINAL_PROMPT=0 "$GIT" clone -q --depth 1 "${url%/}.git" "$WORK/latest/$folder" 2>/dev/null \
      || { echo "$folder: couldn't fetch $url (nothing published, so the latest is never replaced by older)" >&2; exit 1; }
    # Each picture changed in the tree since its commit goes over the clone's, and only that one: the repository may
    # have a newer picture of its own beside it.
    tree="Resources/Starters/$folder/tree"
    [[ -d "$tree/.git" ]] || continue
    "$GIT" -C "$tree" status --porcelain -z --no-renames -- .github 2>/dev/null | while IFS= read -r -d '' entry; do
      picture="${${entry:3}%/}"
      echo "$folder: $picture drawn since its commit"
      rm -rf "$WORK/latest/$folder/$picture"
      if [[ -e "$tree/$picture" ]]; then
        mkdir -p "$WORK/latest/$folder/${picture:h}"
        cp -R "$tree/$picture" "$WORK/latest/$folder/$picture"
      fi
    done
  done
  STAGE_STARTERS=1 "$BIN" --stage-starter-repos "$WORK/trees" "$WORK/pages" --trees "$WORK/latest"
fi

failed=0
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
    "$GIT" "${signed[@]}" clone -q "https://github.com/$repo.git" "$clone"
  else
    gh repo create "$repo" --public >/dev/null
    gh api -X PUT "orgs/$ACCOUNT/teams/$TEAM/repos/$repo" -f permission=push >/dev/null \
      || echo "$repo: couldn't give the $TEAM team push access; do it on GitHub" >&2
    (cd "$clone" && "$GIT" init -q -b main)
  fi
  # The staged tree in place of what's there: one commit of the difference, or none.
  find "$clone" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  cp -R "$tree"/. "$clone"/
  cd "$clone"
  "$GIT" add -A
  if "$GIT" rev-parse -q --verify HEAD >/dev/null && "$GIT" diff --cached --quiet; then
    echo "$repo: unchanged"
  else
    "$GIT" -c user.name="Lamp" -c user.email="$LOGIN@users.noreply.github.com" commit -q -m "$(sed -n 's/^name: *//p' "$OLDPWD/$starter" | head -1) from Lamp"
    "$GIT" "${signed[@]}" push -q "https://github.com/$repo.git" HEAD:main
    echo "$repo: $("$GIT" rev-parse --short HEAD)"
  fi
  sha="$("$GIT" rev-parse HEAD)"
  cd "$OLDPWD"
  # What it is, in its own words (the manifest's description), as the repository's description.
  about="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("description",""))' "$tree/lamp-app.json" 2>/dev/null || true)"
  [[ -n "$about" ]] && gh repo edit "$repo" --description "$about" >/dev/null
  # A game's page: the gh-pages branch, one commit of the difference, served by GitHub Pages.
  if [[ -d "$WORK/pages/$folder" ]]; then
    site="$WORK/sites/$folder"
    mkdir -p "$site"
    (
      cd "$site"
      "$GIT" init -q -b gh-pages
      if "$GIT" "${signed[@]}" fetch -q "https://github.com/$repo.git" gh-pages 2>/dev/null; then
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
        if ! said="$("$GIT" "${signed[@]}" push -q "https://github.com/$repo.git" HEAD:gh-pages 2>&1)"; then
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
  # The pin: the address and commit into starter.md's front matter, and the tree fetched at it.
  /usr/bin/python3 scripts/starter-commit.py "$starter" "https://github.com/$repo" "$sha"
  scripts/fetch-starters.sh "$folder" >/dev/null || failed=1
done
(( failed )) && exit 1
(( DRY )) || echo "Commit the starter.md files that changed (git status Resources/Starters)."
exit 0
