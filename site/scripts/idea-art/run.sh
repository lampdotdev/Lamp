#!/bin/bash
# Draws every idea's icon and picture that isn't drawn yet, eight at a time, then puts them in src/assets/ideas/.
# Needs Codex signed in with ChatGPT, and bash 4 or later for finish.sh. About a minute an image.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/.work"; mkdir -p "$WORK/raw" "$WORK/logs"
cd "$HERE/../.."
node --experimental-strip-types -e 'import("./src/lib/ideas.ts").then(m => { for (const i of m.IDEAS) console.log(`${i.category}|${i.name}|${i.form}`) })' 2>/dev/null > "$WORK/forms.txt"
python3 "$HERE/prompts.py"
swiftc -O "$HERE/tile.swift" -o "$WORK/tile" 2>/dev/null
python3 -c "import json,sys; [print(j['slug'], j['kind']) for j in json.load(open(sys.argv[1]))]" "$WORK/jobs.json" | xargs -P 8 -L 1 "$HERE/draw.sh"
bash "$HERE/finish.sh"
