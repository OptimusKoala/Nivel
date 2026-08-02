#!/bin/bash
# scripts/import-avatars.sh
# Régénère App/Assets.xcassets/Avatars/ depuis design/icons/{boy,girl}.png :
# les deux Nivelito des cartes de profil de l'onboarding (spec icônes catalogues §3.2).
#
# PNG et non JPEG, contrairement à import-sport-images.sh : ces illustrations sont
# DÉTOURÉES et se posent sur la carte blanche — un JPEG remplirait le fond en noir.
# 384 px pour un affichage à 72 pt (216 px en @3x) : de la marge, sans embarquer les
# 900 Ko de la source.
# Idempotent : relancer après avoir retouché une source.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="design/icons"
DST="App/Assets.xcassets/Avatars"

rm -rf "$DST"
mkdir -p "$DST"
cat > "$DST/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "provides-namespace" : true }
}
JSON

for id in boy girl; do
  src="$SRC/$id.png"
  [ -f "$src" ] || { echo "ERREUR : source manquante $src" >&2; exit 1; }
  dir="$DST/$id.imageset"
  mkdir -p "$dir"
  sips -Z 384 -s format png "$src" --out "$dir/$id.png" >/dev/null
  [ -s "$dir/$id.png" ] || { echo "ERREUR : conversion échouée pour $src" >&2; exit 1; }
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$id.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
done

echo "OK : 2 imagesets d'avatars générés"
