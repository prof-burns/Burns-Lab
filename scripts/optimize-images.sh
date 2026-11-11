#!/bin/bash
# Resize images for the web and drop them in images/.
# Full-size originals stay out of the repo; keep them wherever you keep lab files.
#
# Usage:  scripts/optimize-images.sh <source-dir> [max-width]
# Example: scripts/optimize-images.sh ~/Desktop/new-lab-photos 1600
#
# Uses sips, which ships with macOS, so there is nothing to install.

SRC=${1:?usage: optimize-images.sh <source-dir> [max-width]}
MAX_WIDTH=${2:-1600}     # longest edge, in pixels
QUALITY=70               # jpeg quality, 0-100
OUT=images               # where the web-sized copies land

mkdir -p "$OUT"

for f in "$SRC"/*.{jpg,jpeg,png,JPG,JPEG,PNG}; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  case "$name" in
    *.png|*.PNG) out="$OUT/${name%.*}.png" ;;   # keep logos and line art as png
    *)           out="$OUT/${name%.*}.jpg" ;;
  esac
  sips -Z "$MAX_WIDTH" -s formatOptions "$QUALITY" "$f" --out "$out" >/dev/null
  echo "$name -> $out ($(du -h "$out" | cut -f1))"
done
