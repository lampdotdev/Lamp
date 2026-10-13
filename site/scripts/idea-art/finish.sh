#!/bin/bash
# Turns what's in raw/ into the site's pictures: icons on Lamp's tile (256px PNG), pictures as 1200px JPEG.
HERE="$(cd "$(dirname "$0")" && pwd)"; ART="$HERE/.work"
DEST="$HERE/../../src/assets/ideas"; mkdir -p "$DEST/icons" "$DEST/thumbs"
declare -A TOP=( [white]="#FFFFFF" [graphite]="#5C5C63" [blue]="#6CC5FF" [indigo]="#9391F7" [purple]="#D29CFF" [pink]="#FF94B4" [red]="#FF8D7D" [orange]="#FFC266" [yellow]="#FFE98A" [green]="#8DE391" [teal]="#72E1E8" )
declare -A BOTTOM=( [white]="#E3E3E8" [graphite]="#1C1C1E" [blue]="#0A6CFF" [indigo]="#4A45D4" [purple]="#9038DB" [pink]="#EE3460" [red]="#E0302A" [orange]="#FF7A00" [yellow]="#FFC400" [green]="#28A745" [teal]="#0E9FB2" )
while IFS='|' read -r name subject bg screen; do
  s=$(python3 -c "import re,sys;print(re.sub(r'[^a-z0-9]+','-',sys.argv[1].lower()).strip('-'))" "$name")
  light=0; [[ $bg == white || $bg == yellow ]] && light=1
  if [ -s "$ART/raw/$s-icon.png" ] && [ ! -s "$DEST/icons/$s.png" ]; then
    "$ART/tile" "$ART/raw/$s-icon.png" "${TOP[$bg]}" "${BOTTOM[$bg]}" $light "$DEST/icons/$s.png" 256 || echo "tile failed $s"
  fi
  if [ -s "$ART/raw/$s-thumb.png" ] && [ ! -s "$DEST/thumbs/$s.jpg" ]; then
    sips -Z 1200 -s format jpeg -s formatOptions 82 "$ART/raw/$s-thumb.png" --out "$DEST/thumbs/$s.jpg" >/dev/null
  fi
done < "$HERE/briefs.txt"
ls "$DEST/icons" | wc -l; ls "$DEST/thumbs" | wc -l
