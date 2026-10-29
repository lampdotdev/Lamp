#!/bin/zsh
# Records each starter's reel from Resources/Starters/<folder>/showcase/ (showcase.json, and what it brings: a photo,
# a recording, data/<name>.json for LampStore to start with) into its fetched tree's .github/showcase/: reel.mp4, loop.webp and poster.png, which scripts/publish-starters.sh then puts up as it does any
# picture drawn in the tree, and its README shows. A starter with no showcase/ is passed over.
#
#   ./build.sh && scripts/showcase-starters.sh            every starter
#   scripts/showcase-starters.sh weddingwords             one, by folder name
#   KEEP=1 scripts/showcase-starters.sh weddingwords      keeps the take's folder, to look at what happened
#
# Each starter is staged with this checkout's own files (as publish-starters.sh stages it), built under its own bundle
# id, and opened with LAMP_SHOWCASE (LampShowcase in LampSupport): its data, AI, location and the person's lines come
# from the script, and it plays the script's steps on its window, which comes to the front for the minute or so that
# takes (a window in the back is drawn with gray controls). Needs Screen & System Audio Recording for whatever runs it,
# ffmpeg, and Python 3 (Pillow and numpy are installed in .build/showcase-python the first time).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

APP=(build/Lamp\ Dev*.app(N/om[1]))
[[ -n "${APP[1]:-}" ]] || { echo "Build Lamp Dev first (./build.sh)." >&2; exit 1; }
BIN="${APP[1]}/Contents/MacOS/${${APP[1]:t}:r}"
command -v ffmpeg >/dev/null || { echo "Install ffmpeg first (brew install ffmpeg)." >&2; exit 1; }

PY=.build/showcase-python
if [[ ! -x "$PY/bin/python" ]] || ! "$PY/bin/python" -c "import PIL, numpy" 2>/dev/null; then
  python3 -m venv "$PY"
  "$PY/bin/pip" -q install pillow numpy
fi
RECORD=.build/showcase/record
if [[ ! -x "$RECORD" || scripts/showcase/record.swift -nt "$RECORD" ]]; then
  mkdir -p "${RECORD:h}"
  xcrun swiftc -O -swift-version 5 scripts/showcase/record.swift -o "$RECORD"
fi

# Waits until the take's log has `$2`, for at most `$3` seconds.
await_event() {
  local log=$1 event=$2 limit=$3 waited=0
  until [[ -f "$log" ]] && cut -f2 "$log" | grep -qx "$event"; do
    sleep 0.25; waited=$((waited + 1))
    (( waited < limit * 4 )) || return 1
  done
}

folders=("$@")
(( $#folders )) || folders=(Resources/Starters/*(N/:t))
failed=0
for folder in "${folders[@]}"; do
  tree="Resources/Starters/$folder/tree"
  board="Resources/Starters/$folder/showcase"
  [[ -f "$board/showcase.json" ]] || { echo "$folder: no showcase/showcase.json, passed over"; continue; }
  [[ -d "$tree" ]] || { echo "$folder: no tree (scripts/fetch-starters.sh)" >&2; failed=1; continue; }
  WORK="$(mktemp -d -t lamp-showcase)"
  mkdir -p "$WORK/latest"
  rsync -a --exclude .build --exclude build --exclude .lamp --exclude .github/showcase "$tree/" "$WORK/latest/$folder/"
  STAGE_STARTERS=1 "$BIN" --stage-starter-repos "$WORK/trees" "$WORK/pages" --trees "$WORK/latest" >/dev/null
  app="$WORK/trees/$folder"
  # Its own bundle id, so nothing it keeps (window positions, defaults) mixes with a copy of it on this Mac.
  id="$(sed -n 's/.*<key>CFBundleIdentifier<\/key><string>\([^<]*\)<.*/\1/p' "$app/build.sh" | head -1)"
  sed -i '' "s/${id//./\\.}/$id.showcase/g" "$app/build.sh"
  defaults delete "$id.showcase" >/dev/null 2>&1 || true
  echo "$folder: building"
  (cd "$app" && ./build.sh) > "$WORK/build.log" 2>&1 || { echo "$folder: the build failed ($WORK/build.log)" >&2; failed=1; continue; }
  bundle=("$app"/build/*.app(N/[1]))
  take="$WORK/take"
  mkdir -p "$take"
  cp -R "$board/." "$take/"
  echo "$folder: recording"
  open -n -g --env LAMP_SHOWCASE="$take" "$bundle" --args -ApplePersistenceIgnoreState YES
  pid=""
  for _ in {1..80}; do pid="$(pgrep -f "$bundle/Contents/MacOS/" | head -1 || true)"; [[ -n "$pid" ]] && break; sleep 0.25; done
  [[ -n "$pid" ]] || { echo "$folder: it didn't open" >&2; failed=1; continue; }
  if ! await_event "$take/events.tsv" ready 60; then
    echo "$folder: its window never came up" >&2; kill "$pid" 2>/dev/null; failed=1; continue
  fi
  # The app begins its steps once the recorder has its first frame and leaves `recording`.
  "$RECORD" "$pid" "$take/raw.mp4" "$take/stop" "$take/recording" > "$take/record.log" 2>&1 &
  recorder=$!
  await_event "$take/events.tsv" end 600 || echo "$folder: the script didn't reach its end" >&2
  sleep 0.5
  touch "$take/stop"
  wait $recorder || { echo "$folder: the recording failed ($take/record.log)" >&2; kill "$pid" 2>/dev/null; failed=1; continue; }
  kill "$pid" 2>/dev/null || true
  if grep -q $'\tmissing\tthe recording\'s first frame' "$take/events.tsv"; then
    echo "$folder: the recording never started, so nothing was played (is Screen Recording allowed?)" >&2; failed=1; continue
  fi
  if grep -q $'\tmissing\t' "$take/events.tsv"; then
    echo "$folder: the script couldn't find: $(grep $'\tmissing\t' "$take/events.tsv" | cut -f3 | paste -sd, -)" >&2
  fi
  echo "$folder: editing"
  "$PY/bin/python" scripts/showcase/edit.py "$take" "$app" "$tree/.github/showcase" "Resources/Starters/$folder/starter.md" \
    || { echo "$folder: the edit failed" >&2; failed=1; continue; }
  if [[ -n "${KEEP:-}" ]]; then echo "$folder: the take is in $take"; else rm -rf "$WORK"; fi
done
exit $failed
