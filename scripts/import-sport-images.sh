#!/bin/bash
# scripts/import-sport-images.sh
# Régénère App/Assets.xcassets/Sport/ depuis design/sport/*.png :
# JPEG 750x750 qualité 80 (~100-150 Ko), un imageset universel single-scale par image.
# Idempotent : relancer après avoir ajouté/retouché une source.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="design/sport"
DST="App/Assets.xcassets/Sport"

rm -rf "$DST"
mkdir -p "$DST"
cat > "$DST/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "provides-namespace" : true }
}
JSON

for src in "$SRC"/*.png; do
  id=$(basename "$src" .png)
  dir="$DST/$id.imageset"
  mkdir -p "$dir"
  sips -Z 750 -s format jpeg -s formatOptions 80 "$src" --out "$dir/$id.jpg" >/dev/null
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$id.jpg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
done

echo "OK : $(ls -d "$DST"/*.imageset | wc -l | tr -d ' ') imagesets générés"
