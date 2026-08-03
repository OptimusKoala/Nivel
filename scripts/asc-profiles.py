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

Le JWT ES256 est signé avec openssl : ni PyJWT ni cryptography ne sont installés, et on
ne va pas imposer des dépendances Python pour deux appels HTTP.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

TEAM_ID = "AXVF69V3LL"
PROFILES = [
    ("Nivel App Store", "com.elitedangereuse.Nivel"),
    ("Nivel Widgets App Store", "com.elitedangereuse.Nivel.Widgets"),
]
PROFILE_TYPE = "IOS_APP_STORE"
INSTALL_DIR = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
API = "https://api.appstoreconnect.apple.com"


def die(message):
    print(f"✗ {message}", file=sys.stderr)
    sys.exit(1)


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """Signature ECDSA DER (SEQUENCE de deux INTEGER) → 64 octets r||s, comme exigé par JWS."""
    if der[0] != 0x30:
        die("signature openssl inattendue (pas une séquence DER)")
    index = 2 if der[1] < 0x80 else 3  # longueur courte ou longue
    parts = []
    for _ in range(2):
        if der[index] != 0x02:
            die("signature openssl inattendue (INTEGER manquant)")
        length = der[index + 1]
        value = der[index + 2 : index + 2 + length]
        parts.append(value.lstrip(b"\x00").rjust(32, b"\x00"))
        index += 2 + length
    return b"".join(parts)


def token(key_path: Path, key_id: str, issuer_id: str) -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=signing_input.encode(), capture_output=True,
    )
    if result.returncode != 0:
        die(f"openssl n'a pas pu signer le jeton : {result.stderr.decode().strip()}")
    return f"{signing_input}.{b64url(der_to_raw(result.stdout))}"


def call(jwt: str, method: str, path: str, body=None):
    request = urllib.request.Request(
        f"{API}{path}", method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        try:
            messages = [
                f"{e.get('title')} — {e.get('detail')}" for e in json.loads(detail).get("errors", [])
            ]
            detail = " | ".join(messages) or detail
        except json.JSONDecodeError:
            pass
        die(f"{method} {path} → HTTP {error.code} : {detail}")


def main():
    key_id = os.environ.get("ASC_KEY_ID") or die("ASC_KEY_ID manquant (voir l'en-tête du script)")
    issuer_id = os.environ.get("ASC_ISSUER_ID") or die("ASC_ISSUER_ID manquant")
    key_path = Path.home() / f".appstoreconnect/private_keys/AuthKey_{key_id}.p8"
    if not key_path.exists():
        die(f"clé introuvable : {key_path}")

    jwt = token(key_path, key_id, issuer_id)

    # Certificat de distribution : celui déjà installé dans le trousseau de cette machine.
    certificates = [
        c for c in call(jwt, "GET", "/v1/certificates?limit=200")["data"]
        if c["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION")
    ]
    if not certificates:
        die("aucun certificat de distribution sur le compte")
    certificate = certificates[0]
    print(f"▸ Certificat : {certificate['attributes']['name']} "
          f"(expire le {certificate['attributes']['expirationDate'][:10]})")

    existing = {p["attributes"]["name"]: p for p in call(jwt, "GET", "/v1/profiles?limit=200")["data"]}
    bundles = {b["attributes"]["identifier"]: b["id"]
               for b in call(jwt, "GET", "/v1/bundleIds?limit=200")["data"]}

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
                call(jwt, "DELETE", f"/v1/profiles/{profile['id']}")
                print(f"▸ {name} : profil périmé supprimé")
            profile = call(jwt, "POST", "/v1/profiles", {
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
            content = call(jwt, "GET", f"/v1/profiles/{profile['id']}")["data"]["attributes"]["profileContent"]
        destination = INSTALL_DIR / f"{profile['attributes']['uuid']}.mobileprovision"
        destination.write_bytes(base64.b64decode(content))
        print(f"   installé : {destination.name}")

    print("✓ Profils prêts. Enchaîner avec ./scripts/release.sh --upload")


if __name__ == "__main__":
    main()
