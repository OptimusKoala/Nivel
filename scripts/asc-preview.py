#!/usr/bin/env python3
"""Téléverse les aperçus vidéo App Store de Nivel.

    python3 scripts/asc-preview.py

Prend les .mp4 de docs/appstore/previews/ dans l'ordre alphabétique (apercu-1…, apercu-2…)
et les envoie dans la version en préparation. Un jeu déjà rempli est vidé d'abord : on ne
laisse pas s'empiler deux générations d'aperçus.

Apple transcode ensuite chaque vidéo de son côté, ce qui prend quelques minutes ; le script
attend le verdict au lieu de laisser croire que tout est passé. Un aperçu refusé (durée,
codec, résolution) le dit ici et pas trois jours plus tard.

Identifiants : voir scripts/asc_auth.py.
"""

import hashlib
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_auth import Session, die  # noqa: E402

APP_ID = "6797520298"
LOCALE = "fr-FR"
PREVIEWS_DIR = Path(__file__).resolve().parent.parent / "docs/appstore/previews"
# 1320 × 2868 relève du bac « 6,7/6,9 pouces » côté Apple, comme les captures.
PREVIEW_TYPE = "IPHONE_67"
# Image d'affiche : l'instant figé montré avant lecture. 3 s, le temps que l'écran soit
# installé et lisible. Format HH:MM:SS:image.
POSTER_TIMECODE = "00:00:03:00"


def version_localization(session):
    versions = session.paged(f"/v1/apps/{APP_ID}/appStoreVersions?limit=10")
    editable = [v for v in versions
                if v["attributes"]["appStoreState"] not in ("READY_FOR_SALE", "REMOVED_FROM_SALE")]
    if not editable:
        die("aucune version modifiable sur la fiche")
    version = editable[0]
    for item in session.paged(
            f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations"):
        if item["attributes"]["locale"].lower() == LOCALE.lower():
            return version["attributes"]["versionString"], item["id"]
    die(f"aucune localisation {LOCALE}")


def preview_set(session, localization_id):
    sets = session.paged(f"/v1/appStoreVersionLocalizations/{localization_id}/appPreviewSets")
    existing = next((s for s in sets if s["attributes"]["previewType"] == PREVIEW_TYPE), None)
    if existing:
        for old in session.paged(f"/v1/appPreviewSets/{existing['id']}/appPreviews"):
            session.call("DELETE", f"/v1/appPreviews/{old['id']}")
        print(f"▸ Jeu d'aperçus {PREVIEW_TYPE} : vidé")
        return existing["id"]

    created = session.call("POST", "/v1/appPreviewSets", {
        "data": {
            "type": "appPreviewSets",
            "attributes": {"previewType": PREVIEW_TYPE},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": localization_id}}},
        }
    })["data"]
    print(f"▸ Jeu d'aperçus {PREVIEW_TYPE} : créé")
    return created["id"]


def push(session, set_id, path):
    data = path.read_bytes()
    reserved = session.call("POST", "/v1/appPreviews", {
        "data": {
            "type": "appPreviews",
            "attributes": {"fileName": path.name, "fileSize": len(data),
                           "previewFrameTimeCode": POSTER_TIMECODE},
            "relationships": {"appPreviewSet": {
                "data": {"type": "appPreviewSets", "id": set_id}}},
        }
    })["data"]

    operations = reserved["attributes"]["uploadOperations"]
    for index, operation in enumerate(operations, 1):
        offset, length = operation["offset"], operation["length"]
        session.upload(operation, data[offset : offset + length])
        print(f"   {path.name} · morceau {index}/{len(operations)}", end="\r", flush=True)

    session.call("PATCH", f"/v1/appPreviews/{reserved['id']}", {
        "data": {"type": "appPreviews", "id": reserved["id"],
                 "attributes": {"uploaded": True,
                                "sourceFileChecksum": hashlib.md5(data).hexdigest()}}
    })
    size = len(data) / 1_048_576
    print(f"   ✓ {path.name} ({size:.1f} Mo, {len(operations)} morceaux)")
    return reserved["id"]


def wait_for_apple(session, preview_ids, minutes=10):
    """Apple transcode les vidéos : tant que l'état n'est pas COMPLETE, rien n'est acquis."""
    deadline = time.time() + minutes * 60
    pending = dict.fromkeys(preview_ids)
    print("▸ Transcodage par Apple")
    while pending and time.time() < deadline:
        for preview_id in list(pending):
            attributes = session.call("GET", f"/v1/appPreviews/{preview_id}")["data"]["attributes"]
            state = (attributes.get("assetDeliveryState") or {})
            name = attributes.get("fileName", preview_id)
            if state.get("state") == "COMPLETE":
                print(f"   ✓ {name} accepté")
                del pending[preview_id]
            elif state.get("errors"):
                print(f"   ✗ {name} refusé : {state['errors']}")
                del pending[preview_id]
        if pending:
            time.sleep(20)
    for preview_id in pending:
        print(f"   … {preview_id} encore en traitement — à revérifier dans l'interface")


def main():
    files = sorted(PREVIEWS_DIR.glob("apercu-*.mp4"))
    if not files:
        die(f"aucun aperçu dans {PREVIEWS_DIR} — lancer ./scripts/preview.sh d'abord")
    if len(files) > 3:
        die(f"{len(files)} aperçus : Apple en accepte 3 au maximum par taille d'écran")

    session = Session()
    version_string, localization_id = version_localization(session)
    print(f"▸ Version {version_string} · {len(files)} aperçu(s) à envoyer")

    set_id = preview_set(session, localization_id)
    preview_ids = [push(session, set_id, path) for path in files]

    # L'ordre d'affichage est porté par la relation, pas par l'ordre d'envoi.
    session.call("PATCH", f"/v1/appPreviewSets/{set_id}/relationships/appPreviews",
                 {"data": [{"type": "appPreviews", "id": i} for i in preview_ids]})
    print(f"▸ Ordre des {len(preview_ids)} aperçus fixé")

    wait_for_apple(session, preview_ids)
    print("\n✓ Aperçus envoyés.")


if __name__ == "__main__":
    main()
