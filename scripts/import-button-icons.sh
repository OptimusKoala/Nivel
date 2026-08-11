#!/bin/bash
# scripts/import-button-icons.sh
# Régénère App/Assets.xcassets/Buttons/ depuis design/icons/button_icon_{eating,sport}.png :
# les deux Nivelito des boutons d'action de l'accueil (spec v1.13 §6.2).
#
# PNG et non JPEG, pour la même raison qu'import-avatars.sh : ces illustrations sont
# DÉTOURÉES et se posent sur la carte du bouton — un JPEG remplirait le fond en noir.
# 384 px pour un affichage à 56 pt (168 px en @3x) : de la marge, sans embarquer les
# 1254 px de la source.
# Idempotent : relancer après avoir retouché une source.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="design/icons"
DST="App/Assets.xcassets/Buttons"

rm -rf "$DST"
mkdir -p "$DST"
cat > "$DST/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "provides-namespace" : true }
}
JSON

for id in button_icon_eating button_icon_sport; do
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

echo "OK : 2 imagesets de boutons générés"
