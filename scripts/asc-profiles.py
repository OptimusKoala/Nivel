#!/usr/bin/env python3
"""Crée (ou récupère) les profils de distribution App Store de Nivel, et les installe.

    python3 scripts/asc-profiles.py

Prérequis — une clé API App Store Connect de rôle « App Manager » ou « Admin »
(App Store Connect › Utilisateurs et accès › Intégrations › Clés d'équipe) :

    ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
    export ASC_KEY_ID=XXXXXXXXXX
    export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

Pourquoi ce script existe : les profils que Xcode fabrique tout seul sont marqués
« Xcode managed » et sont refusés en signature manuelle, seule façon d'archiver ici
(la team n'a aucun appareil enregistré, donc aucun profil de développement possible).
On crée donc deux profils App Store « classiques », que project.yml nomme explicitement.
"""

import base64
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_auth import Session, die  # noqa: E402

PROFILES = [
    ("Nivel App Store", "com.elitedangereuse.Nivel"),
    ("Nivel Widgets App Store", "com.elitedangereuse.Nivel.Widgets"),
]
PROFILE_TYPE = "IOS_APP_STORE"
INSTALL_DIR = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"


def main():
    session = Session()

    # Certificat de distribution : celui déjà installé dans le trousseau de cette machine.
    certificates = [
        c for c in session.paged("/v1/certificates?limit=200")
        if c["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION")
    ]
    if not certificates:
        die("aucun certificat de distribution sur le compte")
    certificate = certificates[0]
    print(f"▸ Certificat : {certificate['attributes']['name']} "
          f"(expire le {certificate['attributes']['expirationDate'][:10]})")

    existing = {p["attributes"]["name"]: p for p in session.paged("/v1/profiles?limit=200")}
    bundles = {b["attributes"]["identifier"]: b["id"]
               for b in session.paged("/v1/bundleIds?limit=200")}

    INSTALL_DIR.mkdir(parents=True, exist_ok=True)
    for name, bundle_identifier in PROFILES:
        if bundle_identifier not in bundles:
            die(f"identifiant d'app absent du compte : {bundle_identifier}")

        profile = existing.get(name)
        if profile and profile["attributes"]["profileState"] == "ACTIVE":
            print(f"▸ {name} : déjà présent, réutilisé")
        else:
            if profile:
                # Un profil invalide (certificat renouvelé, capacité ajoutée) ne se
                # met pas à jour : il se supprime et se recrée.
                session.call("DELETE", f"/v1/profiles/{profile['id']}")
                print(f"▸ {name} : profil périmé supprimé")
            profile = session.call("POST", "/v1/profiles", {
                "data": {
                    "type": "profiles",
                    "attributes": {"name": name, "profileType": PROFILE_TYPE},
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bundles[bundle_identifier]}},
                        "certificates": {"data": [{"type": "certificates", "id": certificate["id"]}]},
                    },
                }
            })["data"]
            print(f"▸ {name} : créé")

        content = profile["attributes"].get("profileContent")
        if not content:  # une réponse de liste ne contient pas le binaire
            content = session.call("GET", f"/v1/profiles/{profile['id']}")["data"]["attributes"]["profileContent"]
        destination = INSTALL_DIR / f"{profile['attributes']['uuid']}.mobileprovision"
        destination.write_bytes(base64.b64decode(content))
        print(f"   installé : {destination.name}")

    print("✓ Profils prêts. Enchaîner avec ./scripts/release.sh --upload")


if __name__ == "__main__":
    main()
