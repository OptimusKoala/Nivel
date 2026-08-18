#!/usr/bin/env python3
"""Remplit la fiche App Store de Nivel et téléverse les captures.

    python3 scripts/asc-fiche.py            # remplit tout
    python3 scripts/asc-fiche.py --textes   # sans les captures

Les textes sont LUS dans docs/appstore/fiche-app-store.md : ce fichier reste la seule
source de vérité, on ne recopie pas la description dans un JSON qui divergerait.
Chaque champ y est un bloc de code précédé de son libellé en gras.

Ce que ce script NE fait pas, parce qu'Apple ne l'expose pas (ou mal) : le questionnaire
de confidentialité (« aucune donnée collectée »), la classification par âge, le prix et
les territoires de diffusion. Ces quatre points restent à cocher dans l'interface.

Identifiants : voir scripts/asc_auth.py.
"""

import hashlib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_auth import Session, die  # noqa: E402

APP_ID = "6797520298"
LOCALE = "fr-FR"
FICHE = Path(__file__).resolve().parent.parent / "docs/appstore/fiche-app-store.md"
SHOTS_DIR = Path(__file__).resolve().parent.parent / "docs/appstore/framed"
# 1320 × 2868 (iPhone 17 Pro Max) relève du bac « 6,7/6,9 pouces » côté Apple.
DISPLAY_TYPE = "APP_IPHONE_67"
PRIMARY_CATEGORY = "HEALTH_AND_FITNESS"
SECONDARY_CATEGORY = "LIFESTYLE"

LABELS = {
    "Nom": "name",
    "Sous-titre": "subtitle",
    "Texte promotionnel": "promotionalText",
    "Description": "description",
    "Nouveautés de cette version": "whatsNew",
    "Mots-clés": "keywords",
    "URL d'assistance": "supportUrl",
    "URL marketing": "marketingUrl",
    "Copyright": "copyright",
    "URL de la politique de confidentialité": "privacyPolicyUrl",
}


def read_fiche() -> dict:
    """Chaque libellé en gras en début de ligne, puis le bloc de code qui le suit."""
    fields, pending, buffer = {}, None, None
    for line in FICHE.read_text().splitlines():
        if buffer is not None:
            if line.startswith("```"):
                fields[pending] = "\n".join(buffer).strip()
                pending, buffer = None, None
            else:
                buffer.append(line)
            continue
        if line.startswith("**"):
            match = re.match(r"\*\*(.+?)\*\*", line)
            label = match.group(1) if match else ""
            pending = LABELS.get(label)  # un gras inconnu remet le compteur à zéro
            continue
        if line.startswith("```") and pending:
            buffer = []
    missing = set(LABELS.values()) - set(fields)
    if missing:
        die(f"champs introuvables dans {FICHE.name} : {', '.join(sorted(missing))}")
    return fields


def localization(session, path, kind):
    """La localisation française d'une collection, quelle que soit sa casse de locale."""
    for item in session.paged(path):
        if item["attributes"]["locale"].lower() == LOCALE.lower():
            return item
    die(f"aucune localisation {LOCALE} pour {kind}")


def push_screenshots(session, localization_id, files):
    sets = session.paged(f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")
    screenshot_set = next(
        (s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None)
    if screenshot_set:
        # Re-remplissage : on repart d'un jeu vide, sinon les captures s'empilent.
        for old in session.paged(f"/v1/appScreenshotSets/{screenshot_set['id']}/appScreenshots"):
            session.call("DELETE", f"/v1/appScreenshots/{old['id']}")
        print(f"▸ Jeu de captures {DISPLAY_TYPE} : vidé")
    else:
        screenshot_set = session.call("POST", "/v1/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {"appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": localization_id}}},
            }
        })["data"]
        print(f"▸ Jeu de captures {DISPLAY_TYPE} : créé")

    uploaded = []
    for path in files:
        data = path.read_bytes()
        reserved = session.call("POST", "/v1/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": screenshot_set["id"]}}},
            }
        })["data"]
        for operation in reserved["attributes"]["uploadOperations"]:
            offset, length = operation["offset"], operation["length"]
            session.upload(operation, data[offset : offset + length])
        session.call("PATCH", f"/v1/appScreenshots/{reserved['id']}", {
            "data": {
                "type": "appScreenshots",
                "id": reserved["id"],
                "attributes": {"uploaded": True,
                               "sourceFileChecksum": hashlib.md5(data).hexdigest()},
            }
        })
        uploaded.append(reserved["id"])
        print(f"   ✓ {path.name}")

    # L'ordre d'affichage est porté par la relation, pas par l'ordre de création.
    session.call("PATCH", f"/v1/appScreenshotSets/{screenshot_set['id']}/relationships/appScreenshots",
                 {"data": [{"type": "appScreenshots", "id": i} for i in uploaded]})
    print(f"▸ Ordre des {len(uploaded)} captures fixé")
    return uploaded


def main():
    only_texts = "--textes" in sys.argv
    fields = read_fiche()
    session = Session()

    # --- Version en préparation ---
    versions = session.paged(f"/v1/apps/{APP_ID}/appStoreVersions?limit=10")
    editable = [v for v in versions
                if v["attributes"]["appStoreState"] not in ("READY_FOR_SALE", "REMOVED_FROM_SALE")]
    if not editable:
        die("aucune version modifiable sur la fiche")
    version = editable[0]
    version_id = version["id"]

    # La build doit correspondre exactement à la version marketing déclarée dans
    # l'app. L'API ne garantit pas l'ordre par défaut : sans ce filtre, une
    # ancienne build VALID pourrait être rattachée à la fiche lors d'un hotfix.
    plist = (Path(__file__).resolve().parent.parent / "App/Info.plist").read_text()
    short_version = re.search(
        r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>", plist).group(1)
    build = next(iter(session.paged(
        f"/v1/builds?filter[app]={APP_ID}&filter[preReleaseVersion.version]={short_version}"
        "&sort=-uploadedDate&limit=10")), None)
    if not build:
        die(f"aucune build envoyée pour la version {short_version}")
    build_version = build["attributes"]["version"]
    if build["attributes"]["processingState"] != "VALID":
        die(f"la build {build_version} est en {build['attributes']['processingState']}, pas VALID")

    # Le numéro de version de la fiche doit être celui du binaire, sinon la build
    # n'est pas rattachable.
    print(f"▸ Version : fiche {version['attributes']['versionString']} → {short_version} "
          f"(build {build_version})")
    session.call("PATCH", f"/v1/appStoreVersions/{version_id}", {
        "data": {"type": "appStoreVersions", "id": version_id,
                 "attributes": {"versionString": short_version,
                                "copyright": fields["copyright"]}}
    })

    session.call("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build",
                 {"data": {"type": "builds", "id": build["id"]}})
    print(f"▸ Build {build_version} rattachée à la version")

    # --- Textes de la version ---
    version_localization = localization(
        session, f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", "la version")
    attributes = {k: fields[k] for k in
                  ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")}
    body = {"data": {"type": "appStoreVersionLocalizations",
                     "id": version_localization["id"],
                     "attributes": {**attributes, "whatsNew": fields["whatsNew"]}}}
    # « Nouveautés » est refusé sur une première mise en vente : rien à annoncer encore.
    if session.call("PATCH", f"/v1/appStoreVersionLocalizations/{version_localization['id']}",
                    body, tolerate=(400, 409, 422)) is None:
        session.call("PATCH", f"/v1/appStoreVersionLocalizations/{version_localization['id']}",
                     {"data": {"type": "appStoreVersionLocalizations",
                               "id": version_localization["id"], "attributes": attributes}})
        print("▸ Textes de la version écrits (sans « Nouveautés » : première mise en vente)")
    else:
        print("▸ Textes de la version écrits")

    # --- Nom, sous-titre, confidentialité, catégories ---
    app_infos = session.paged(f"/v1/apps/{APP_ID}/appInfos")
    app_info = next((i for i in app_infos
                     if i["attributes"]["appStoreState"] not in ("READY_FOR_SALE",)), app_infos[0])
    info_localization = localization(
        session, f"/v1/appInfos/{app_info['id']}/appInfoLocalizations", "les informations d'app")
    session.call("PATCH", f"/v1/appInfoLocalizations/{info_localization['id']}", {
        "data": {"type": "appInfoLocalizations", "id": info_localization["id"],
                 "attributes": {"name": fields["name"], "subtitle": fields["subtitle"],
                                "privacyPolicyUrl": fields["privacyPolicyUrl"]}}
    })
    print(f"▸ Nom « {fields['name']} », sous-titre « {fields['subtitle']} » et URL de "
          f"confidentialité écrits")

    if session.call("PATCH", f"/v1/appInfos/{app_info['id']}", {
        "data": {"type": "appInfos", "id": app_info["id"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": PRIMARY_CATEGORY}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": SECONDARY_CATEGORY}},
        }}
    }, tolerate=(400, 409, 422)) is None:
        print("▸ Catégories refusées par l'API — à choisir dans l'interface "
              f"({PRIMARY_CATEGORY} / {SECONDARY_CATEGORY})")
    else:
        print(f"▸ Catégories : {PRIMARY_CATEGORY} / {SECONDARY_CATEGORY}")

    # --- Captures ---
    if only_texts:
        print("▸ Captures ignorées (--textes)")
    else:
        files = sorted(SHOTS_DIR.glob("*.png"))
        if not files:
            die(f"aucune capture dans {SHOTS_DIR}")
        push_screenshots(session, version_localization["id"], files)

    print("\n✓ Fiche remplie. Restent à cocher dans l'interface, qu'Apple n'expose pas :")
    print("   · Confidentialité → « Non, nous ne collectons aucune donnée »")
    print("   · Classification par âge → tout à « aucun » (résultat 4+)")
    print("   · Prix → Gratuit · Disponibilité → France uniquement")


if __name__ == "__main__":
    main()
