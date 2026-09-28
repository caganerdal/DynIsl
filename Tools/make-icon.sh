#!/bin/zsh
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swift Tools/make-icon.swift "$TMP/icon-1024.png" >/dev/null
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/icon-1024.png" Resources/AppIcon-1024.png
rm -rf "$TMP"
echo "Hazır: Resources/AppIcon.icns"
