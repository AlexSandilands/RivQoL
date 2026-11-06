#!/usr/bin/env bash
# Build the addon icon files from Media/Logo.svg (the single source):
#   Media/Logo-400.png  400x400, for CurseForge (its avatar needs at least 400x400)
#   Media/Logo-512.png  512x512, for Wago and anywhere a larger square is wanted
#   Media/Icon.tga      64x64, 32-bit uncompressed with alpha; the game's
#                       ## IconTexture and the /rq window title use this
# Needs rsvg-convert (librsvg) and magick (ImageMagick 7).
set -euo pipefail

media="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Media"
svg="$media/Logo.svg"

rsvg-convert -w 400 -h 400 "$svg" -o "$media/Logo-400.png"
rsvg-convert -w 512 -h 512 "$svg" -o "$media/Logo-512.png"
rsvg-convert -w 64 -h 64 "$svg" -o "$media/.icon-64.png"
magick "$media/.icon-64.png" -alpha on -depth 8 -compress none -define tga:image-origin=top-left "TGA:$media/Icon.tga"
rm -f "$media/.icon-64.png"
echo "Built Logo-400.png, Logo-512.png, Icon.tga in $media"
