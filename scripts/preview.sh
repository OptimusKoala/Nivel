#!/bin/bash
# Filme les aperçus vidéo App Store de Nivel (« app previews »).
#
#   ./scripts/preview.sh                 # les deux aperçus
#   ./scripts/preview.sh testTourRepas   # un seul, pour itérer
#
# Produit, dans docs/appstore/previews/ :
#   apercu-1-repas.mp4 · apercu-2-sport.mp4    prêts pour App Store Connect
#   brut-*.mov · tournage-*.log                l'enregistrement et le journal des gestes
#
# Fonctionnement : `simctl io recordVideo` filme l'écran du simulateur pendant que la
# cible NivelUITests (schéma NivelPreview) promène l'app — laquelle tourne en mode
# captures, donc sur le profil de démonstration en mémoire, jamais sur de vraies données.
#
# Contraintes Apple pour un aperçu : 15 à 30 s, H.264, 30 im/s au plus, et une piste
# audio (une vidéo sans piste audio du tout est refusée). L'encodage est fait par
# scripts/encode-preview.swift, qui n'utilise que des briques du système : le ffmpeg de
# Homebrew de cette machine est cassé (libbluray absent de son Cellar), et la publication
# d'une app n'a pas à dépendre d'un paquet tiers.

set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_NAME="iPhone 17 Pro Max"
BUNDLE_ID="com.elitedangereuse.Nivel"
OUT_DIR="docs/appstore/previews"
MAX_SECONDS=29
MIN_SECONDS=15

# Nom du test → nom du fichier produit. Un argument FILTRE cette liste (il ne renomme
# rien) : retourner une seule visite doit écraser son propre fichier, pas en créer un autre.
ALL_TOURS=("testTourRepas:apercu-1-repas" "testTourSport:apercu-2-sport")
TOURS=()
if [[ $# -ge 1 ]]; then
  for name in "$@"; do
    for tour in "${ALL_TOURS[@]}"; do
      [[ "${tour%%:*}" == "$name" ]] && TOURS+=("$tour")
    done
  done
  [[ ${#TOURS[@]} -gt 0 ]] || {
    echo "✗ visite inconnue : $* (connues : ${ALL_TOURS[*]%%:*})"; exit 2; }
else
  TOURS=("${ALL_TOURS[@]}")
fi

mkdir -p "$OUT_DIR"

DEVICE_ID=$(xcrun simctl list devices available -j \
  | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next(x['udid'] for v in d.values() for x in v if x['name']=='$DEVICE_NAME'))")

echo "▸ Simulateur $DEVICE_NAME"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b

# Barre d'état figée : sans ça, l'heure et la batterie changent d'un tournage à l'autre.
xcrun simctl status_bar "$DEVICE_ID" override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

echo "▸ Compilation de la visite guidée"
xcodebuild -project Nivel.xcodeproj -scheme NivelPreview \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" -quiet build-for-testing

produced=()
for tour in "${TOURS[@]}"; do
  test_name="${tour%%:*}"
  base="${tour##*:}"
  raw="$OUT_DIR/brut-$base.mov"
  final="$OUT_DIR/$base.mp4"
  log="$OUT_DIR/tournage-$base.log"

  echo "▸ Tournage : $test_name"
  xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
  rm -f "$raw" "$log" "$OUT_DIR/recorder-$base.log"

  xcrun simctl io "$DEVICE_ID" recordVideo --codec=h264 --force "$raw" \
    2>"$OUT_DIR/recorder-$base.log" &
  recorder=$!
  # simctl écrit « Recording started » quand la PREMIÈRE image est encodée : c'est le
  # zéro de la bande. Un repère pris avant serait faux de plusieurs secondes.
  until grep -q "Recording started" "$OUT_DIR/recorder-$base.log" 2>/dev/null; do sleep 0.2; done
  record_epoch=$(python3 -c "import time;print(time.time())")

  xcodebuild -project Nivel.xcodeproj -scheme NivelPreview \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
    -only-testing:"NivelUITests/PreviewTour/$test_name" \
    test-without-building > "$log" 2>&1 || true

  # SIGINT (et non kill -9) : c'est ce qui fait finaliser le conteneur QuickTime.
  kill -INT $recorder 2>/dev/null || true
  wait $recorder 2>/dev/null || true

  [[ -f "$raw" ]] || { echo "   ✗ aucun enregistrement produit"; exit 1; }

  grep -E "^TOUR: " "$log" | sed 's/^TOUR: /   /' || true
  grep -q "^TOUR: MANQUÉ" "$log" && echo "   ⚠️  gestes manqués ci-dessus : temps morts à l'image"

  start_epoch=$(grep -m1 "^TOUR: START " "$log" | awk '{print $3}')
  end_epoch=$(grep -m1 "^TOUR: END " "$log" | awk '{print $3}')
  [[ -n "$start_epoch" && -n "$end_epoch" ]] || {
    echo "   ✗ repères de visite absents : elle n'est pas allée au bout"; exit 1; }

  # Décalage = premier écran de l'app − première image filmée. Durée = la visite,
  # plafonnée à la limite d'Apple.
  offset=$(python3 -c "print(round(max(0.0, $start_epoch - $record_epoch), 2))")
  span=$(python3 -c "print(round(min($MAX_SECONDS, $end_epoch - $start_epoch), 2))")
  full=$(python3 -c "print(round($end_epoch - $start_epoch, 1))")
  echo "   visite de $full s, gardée à partir de $offset s de la bande"
  python3 -c "
import sys
full, mn = $full, $MIN_SECONDS
if full > $MAX_SECONDS:
    print(f'   ⚠️  visite de {full} s tronquée à $MAX_SECONDS s : la fin n\'apparaîtra pas')
elif full < mn:
    print(f'   ✗ visite de {full} s, en dessous des {mn} s exigées par Apple'); sys.exit(1)
"

  swift scripts/encode-preview.swift "$raw" "$final" "$offset" "$span" 2>/dev/null | sed 's/^/   /'
  produced+=("$final")
done

xcrun simctl status_bar "$DEVICE_ID" clear
echo "✓ ${#produced[@]} aperçu(s) : ${produced[*]}"
echo "  téléverser avec : python3 scripts/asc-preview.py"
