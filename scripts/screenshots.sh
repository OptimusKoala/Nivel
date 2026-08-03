#!/bin/bash
# Captures App Store de Nivel — écrans bruts puis habillés (accroche + cadre).
#
#   ./scripts/screenshots.sh
#
# Produit :
#   docs/appstore/raw/*.png          captures brutes du simulateur (1320 × 2868)
#   docs/appstore/framed/*.png       captures habillées, prêtes pour App Store Connect
#
# L'app est lancée en mode DEBUG « --nivel-screenshots » : store en mémoire garni
# d'un profil de démonstration (App/Support/ScreenshotSupport.swift). Aucune donnée
# réelle n'est touchée, et rien de ce mode n'existe dans le binaire de release.
#
# iPhone 17 Pro Max = 6,9 pouces = 1320 × 2868, la seule taille exigée par Apple
# pour l'iPhone ; App Store Connect redimensionne pour les écrans plus petits.

set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_NAME="iPhone 17 Pro Max"
BUNDLE_ID="com.elitedangereuse.Nivel"
RAW_DIR="docs/appstore/raw"
SCHEME="Nivel"

mkdir -p "$RAW_DIR"

echo "▸ Build (Debug, simulateur)"
xcodebuild -project Nivel.xcodeproj -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -configuration Debug -quiet build

APP_PATH=$(xcodebuild -project Nivel.xcodeproj -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" -configuration Debug \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {d=$2} / FULL_PRODUCT_NAME/ {n=$2} END {print d"/"n}')

DEVICE_ID=$(xcrun simctl list devices available -j \
  | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next(x['udid'] for v in d.values() for x in v if x['name']=='$DEVICE_NAME'))")

echo "▸ Simulateur $DEVICE_NAME ($DEVICE_ID)"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b

# Barre d'état figée : 9 h 41, réseau et batterie pleins — pas d'heure ni de
# batterie aléatoire d'une capture à l'autre.
xcrun simctl status_bar "$DEVICE_ID" override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

xcrun simctl install "$DEVICE_ID" "$APP_PATH"

# Écran → thème. L'accueil est capturé deux fois : Crème et Nuit douce (les
# 4 thèmes sont un argument de vente, autant le montrer).
capture() {
  local name="$1" screen="$2" theme="$3" wait="${4:-3}"
  echo "▸ $name"
  xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" \
    --nivel-screenshots -nivelScreen "$screen" -nivel.theme "$theme" >/dev/null
  sleep "$wait"
  xcrun simctl io "$DEVICE_ID" screenshot --type=png "$RAW_DIR/$name.png" 2>/dev/null
}

capture 01-home     home     creme
capture 02-meallog  meallog  creme 4
capture 03-sport    sport    creme
capture 04-session  session  creme 4
capture 05-step     step     creme 4
capture 06-progress progress creme
capture 07-quests   quests   creme
capture 08-night    home     nuit-douce

xcrun simctl status_bar "$DEVICE_ID" clear

echo "▸ Habillage"
swift scripts/frame-screenshots.swift

echo "✓ Captures prêtes dans docs/appstore/framed/"
