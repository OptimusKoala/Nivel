"""Accès à l'API App Store Connect : jeton ES256 et appels HTTP.

Partagé par `asc-profiles.py` (profils de signature) et `asc-fiche.py` (fiche App Store).

Le JWT est signé avec openssl : ni PyJWT ni cryptography ne sont installés sur cette
machine, et on n'impose pas de dépendances Python pour quelques appels HTTP.

Identifiants attendus dans l'environnement :
    ASC_KEY_ID     le nom du fichier ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8
    ASC_ISSUER_ID  l'« Issuer ID » du compte (Utilisateurs et accès › Intégrations)
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


class Session:
    """Une session d'API. Le jeton se renouvelle tout seul : le téléversement des
    captures dure plus longtemps que la validité d'un jeton (20 min au maximum)."""

    LIFETIME = 900
    REFRESH_AFTER = 600

    def __init__(self):
        self.key_id = os.environ.get("ASC_KEY_ID") or die("ASC_KEY_ID manquant")
        self.issuer_id = os.environ.get("ASC_ISSUER_ID") or die("ASC_ISSUER_ID manquant")
        self.key_path = Path.home() / f".appstoreconnect/private_keys/AuthKey_{self.key_id}.p8"
        if not self.key_path.exists():
            die(f"clé introuvable : {self.key_path}")
        self._token = None
        self._issued_at = 0

    @property
    def token(self) -> str:
        if self._token is None or time.time() - self._issued_at > self.REFRESH_AFTER:
            header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
            now = int(time.time())
            payload = {"iss": self.issuer_id, "iat": now, "exp": now + self.LIFETIME,
                       "aud": "appstoreconnect-v1"}
            signing_input = (f"{b64url(json.dumps(header).encode())}."
                             f"{b64url(json.dumps(payload).encode())}")
            result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(self.key_path)],
                                    input=signing_input.encode(), capture_output=True)
            if result.returncode != 0:
                die(f"openssl n'a pas pu signer le jeton : {result.stderr.decode().strip()}")
            self._token = f"{signing_input}.{b64url(der_to_raw(result.stdout))}"
            self._issued_at = now
        return self._token

    def call(self, method: str, path: str, body=None, tolerate=()):
        """Appel JSON. `tolerate` liste les codes HTTP à renvoyer au lieu d'arrêter le
        script (ex. 409 quand une ressource existe déjà)."""
        request = urllib.request.Request(
            f"{API}{path}" if path.startswith("/") else path, method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            if error.code in tolerate:
                return None
            detail = error.read().decode()
            try:
                messages = [f"{e.get('title')} — {e.get('detail')}"
                            for e in json.loads(detail).get("errors", [])]
                detail = " | ".join(messages) or detail
            except json.JSONDecodeError:
                pass
            die(f"{method} {path} → HTTP {error.code} : {detail}")

    def upload(self, operation: dict, chunk: bytes):
        """Envoi d'un morceau de fichier, selon l'`uploadOperation` dicté par Apple
        (URL, méthode et en-têtes viennent de la réponse, on n'invente rien)."""
        request = urllib.request.Request(operation["url"], method=operation["method"], data=chunk)
        for header in operation.get("requestHeaders", []):
            request.add_header(header["name"], header["value"])
        try:
            with urllib.request.urlopen(request) as response:
                response.read()
        except urllib.error.HTTPError as error:
            die(f"téléversement refusé : HTTP {error.code} {error.read().decode()[:200]}")

    def paged(self, path: str):
        """Toutes les pages d'une collection, concaténées."""
        items = []
        while path:
            page = self.call("GET", path)
            items.extend(page.get("data", []))
            path = (page.get("links") or {}).get("next")
        return items
