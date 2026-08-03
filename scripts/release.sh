#!/bin/bash
# Archive, signe, vérifie et envoie Nivel à App Store Connect.
#
#   ./scripts/release.sh            # archive + export + vérifications (pas d'envoi)
#   ./scripts/release.sh --upload   # idem puis envoi vers App Store Connect
#
# L'envoi exige une clé API App Store Connect (App Store Connect › Utilisateurs et accès ›
# Intégrations › Clés d'équipe, rôle « App Manager ») :
#   - le fichier AuthKey_XXXXXXXXXX.p8 dans ~/.appstoreconnect/private_keys/
#   - export ASC_KEY_ID=XXXXXXXXXX
#   - export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# Deux pièges de cette machine, traités ici, à ne pas « simplifier » :
#
# 1. PATH SYSTÈME pour l'export. Le rsync 3.4.4 de Homebrew masque celui d'Apple et
#    rejette l'option --extended-attributes qu'Xcode passe en fabriquant l'IPA
#    (« rsync error: syntax or usage error (code 1) »). On force donc un PATH système
#    pour les étapes xcodebuild d'export.
#
# 2. SIGNATURE MANUELLE en Release (réglée dans project.yml, pas ici). La signature
#    automatique réclame un profil de DÉVELOPPEMENT à l'archivage, or la team n'a aucun
#    appareil enregistré. Archiver sans signature fonctionne, mais l'export perd alors
#    les entitlements HealthKit et App Group — le binaire livré serait cassé en silence.
#    D'où la vérification obligatoire des entitlements ci-dessous.

set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="AXVF69V3LL"
BUNDLE_ID="com.elitedangereuse.Nivel"
OUT=".build/release"
ARCHIVE="$OUT/Nivel.xcarchive"
IPA="$OUT/export/Nivel.ipa"
SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ Profils de distribution"
python3 scripts/asc-profiles.py

echo "▸ Projet Xcode"
xcodegen generate

echo "▸ Tests (logique pure + app)"
(cd NivelCore && swift test --quiet)
xcodebuild -project Nivel.xcodeproj -scheme Nivel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -quiet test

echo "▸ Archive (Release, appareil, signature distribution)"
xcodebuild -project Nivel.xcodeproj -scheme Nivel -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -quiet archive

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>$BUNDLE_ID</key>
		<string>Nivel App Store</string>
		<key>$BUNDLE_ID.Widgets</key>
		<string>Nivel Widgets App Store</string>
	</dict>
	<key>uploadSymbols</key>
	<true/>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
EOF

echo "▸ Export de l'IPA"
env PATH="$SYSTEM_PATH" xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist" -quiet

echo "▸ Vérification du binaire signé"
rm -rf "$OUT/check" && mkdir -p "$OUT/check"
(cd "$OUT/check" && unzip -q "../export/Nivel.ipa")
APP="$OUT/check/Payload/Nivel.app"

# Les quatre invariants qu'un export raté casse en silence.
# Sorties capturées AVANT d'être filtrées : `codesign … | grep -q` renverrait 141
# sous `set -o pipefail` (grep -q sort au premier match et casse le tuyau), et la
# vérification échouerait sur un binaire parfaitement signé.
ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert xml1 -o - -)
SIGNATURE=$(codesign -dv --verbose=2 "$APP" 2>&1)

fail=false
# check <libellé> <motif> <texte à fouiller>
check() {
  if grep -q "$2" <<< "$3"; then echo "   ✓ $1"; else echo "   ✗ $1 MANQUANT"; fail=true; fi
}
check "entitlement HealthKit"        "com.apple.developer.healthkit"           "$ENTITLEMENTS"
check "entitlement App Group"        "com.apple.security.application-groups"   "$ENTITLEMENTS"
check "identifiant d'application"    "$TEAM_ID.$BUNDLE_ID"                     "$ENTITLEMENTS"
check "signature Apple Distribution" "Apple Distribution: L'ELITE DANGEREUSE"  "$SIGNATURE"

# Les DEUX chaînes HealthKit : la validation Apple (erreur 90683) réclame aussi celle
# d'écriture dès que HealthKit est lié, alors que Nivel ne demande que la lecture.
PLIST=$(plutil -convert xml1 -o - "$APP/Info.plist")
check "NSHealthShareUsageDescription"  "NSHealthShareUsageDescription"  "$PLIST"
check "NSHealthUpdateUsageDescription" "NSHealthUpdateUsageDescription" "$PLIST"

# iPhone uniquement : une app universelle en portrait strict fait râler l'archive et
# obligerait à fournir en plus des captures iPad 13 pouces.
FAMILY=$(plutil -extract UIDeviceFamily raw "$APP/Info.plist" | tr -d '[:space:]')
if [[ "$FAMILY" == "1" ]]; then
  echo "   ✓ iPhone uniquement"
else
  echo "   ✗ UIDeviceFamily = $FAMILY, attendu 1 (iPhone seul)"; fail=true
fi
for manifest in "$APP/PrivacyInfo.xcprivacy" "$APP/PlugIns/NivelWidgets.appex/PrivacyInfo.xcprivacy"; do
  if [[ -f "$manifest" ]]; then echo "   ✓ $(basename "$(dirname "$manifest")")/PrivacyInfo.xcprivacy";
  else echo "   ✗ manifeste de confidentialité manquant : $manifest"; fail=true; fi
done

VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw "$APP/Info.plist")
echo "   → version $VERSION (build $BUILD), $(du -h "$IPA" | cut -f1)"

if $fail; then
  echo "✗ Le binaire est incomplet — ne PAS l'envoyer. Voir les lignes ✗ ci-dessus."
  exit 1
fi

if ! $UPLOAD; then
  echo "✓ IPA prête : $IPA (envoi non demandé — relancer avec --upload)"
  exit 0
fi

: "${ASC_KEY_ID:?ASC_KEY_ID manquant (voir l'en-tête de ce script)}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID manquant (voir l'en-tête de ce script)}"

echo "▸ Validation par Apple"
env PATH="$SYSTEM_PATH" xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "▸ Envoi vers App Store Connect"
env PATH="$SYSTEM_PATH" xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "✓ Build $VERSION ($BUILD) envoyée. Le traitement par Apple prend ~15 min,"
echo "  puis la build apparaît dans la version en préparation de la fiche."
