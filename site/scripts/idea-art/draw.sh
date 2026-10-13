#!/bin/bash
# Draws one image with Codex's image generation, signed in with ChatGPT: $1 is an idea's slug, $2 icon or thumb.
# Skips one already drawn, so a run that stopped can be started again. Codex waits for more input on stdin
# unless it's closed, so it gets none.
WORK="$(cd "$(dirname "$0")" && pwd)/.work"
out="$WORK/raw/$1-$2.png"
[ -s "$out" ] && exit 0
prompt=$(python3 -c "import json,sys; print(next(j['prompt'] for j in json.load(open(sys.argv[1])) if j['slug'] == sys.argv[2] and j['kind'] == sys.argv[3]))" "$WORK/jobs.json" "$1" "$2")
for attempt in 1 2; do
  codex exec --skip-git-repo-check -s workspace-write -C "$WORK/raw" \
    "Use your image generation tool to create exactly one image from this prompt, then copy the generated PNG file to $out and reply only with that path. Do not edit the image or do anything else. Prompt: $prompt" \
    < /dev/null > "$WORK/logs/$1-$2.log" 2>&1
  [ -s "$out" ] && { echo "ok $1-$2"; exit 0; }
done
echo "FAILED $1-$2"
