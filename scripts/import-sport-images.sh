#!/bin/bash
# scripts/import-sport-images.sh
# Régénère App/Assets.xcassets/Sport/ depuis design/sport/*.png :
# JPEG 750x750 qualité 80 (~100-150 Ko), un imageset universel single-scale par image.
# Idempotent : relancer après avoir ajouté/retouché une source.
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/.."

SRC="design/sport"
DST="App/Assets.xcassets/Sport"

sources=("$SRC"/*.png)
if [ "${#sources[@]}" -eq 0 ]; then
  echo "ERREUR : aucune source PNG trouvée dans $SRC" >&2
  exit 1
fi

catalog_ids=$(grep -ho '"id": *"[a-z_]*"' \
  NivelCore/Sources/NivelCore/Resources/{activities,sessions}.json \
  | sed 's/.*"\(.*\)"$/\1/' | sort)
source_ids=$(printf '%s\n' "${sources[@]}" | xargs -n1 basename | sed 's/\.png$//' | sort)
if ! diff <(echo "$catalog_ids") <(echo "$source_ids") >/dev/null; then
  echo "ERREUR : sources design/sport et ids de catalogue désynchronisés :" >&2
  diff <(echo "$catalog_ids") <(echo "$source_ids") >&2
  exit 1
fi

rm -rf "$DST"
mkdir -p "$DST"
cat > "$DST/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "provides-namespace" : true }
}
JSON

for src in "${sources[@]}"; do
  id=$(basename "$src" .png)
  dir="$DST/$id.imageset"
  mkdir -p "$dir"
  sips -Z 750 -s format jpeg -s formatOptions 80 "$src" --out "$dir/$id.jpg" >/dev/null
  [ -s "$dir/$id.jpg" ] || { echo "ERREUR : conversion échouée pour $src" >&2; exit 1; }
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$id.jpg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
done

echo "OK : ${#sources[@]} imagesets générés"
