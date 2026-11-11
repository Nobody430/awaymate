"""Creates an Apple Distribution certificate + App Store profiles via the App Store Connect API.

Writes into OUT_DIR: dist.p12 (password in P12_PASSWORD env), <uuid>.mobileprovision files,
ExportOptions.plist. Profiles are named "CI <bundle id>" (referenced by the Xcode projects).
"""
import base64
import hashlib
import json
import os
import plistlib
import sys
import time

import jwt
import requests
from cryptography import x509
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_IDS = ["com.nobody430.skylog", "com.nobody430.skylog.widgets"]


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, params=None, ok=(200, 201, 204)):
    r = requests.request(method, API + path, params=params, json=body,
                         headers={"Authorization": f"Bearer {token()}"}, timeout=60)
    if r.status_code not in ok:
        print(f"::error::{method} {path} -> {r.status_code}: {r.text[:500]}")
        sys.exit(1)
    return r.json() if r.content else {}


def main(out):
    os.makedirs(out, exist_ok=True)
    password = os.environ["P12_PASSWORD"]

    cache_dir = os.environ.get("CERT_CACHE", "")
    fernet = Fernet(base64.urlsafe_b64encode(hashlib.sha256(os.environ["ASC_KEY_P8"].encode()).digest()))
    key = x509_cert = cert_id = None

    # 1) Reuse the cached certificate if it is still valid
    meta_path = os.path.join(cache_dir, "cert.json") if cache_dir else ""
    if meta_path and os.path.exists(meta_path):
        try:
            meta = json.load(open(meta_path))
            r = requests.get(f"{API}/certificates/{meta['id']}", headers={"Authorization": f"Bearer {token()}"}, timeout=30)
            if r.status_code == 200:
                blob = fernet.decrypt(open(os.path.join(cache_dir, "cert.enc"), "rb").read())
                key_pem, cert_pem = blob.split(b"\n----SPLIT----\n")
                key = serialization.load_pem_private_key(key_pem, password=None)
                x509_cert = x509.load_pem_x509_certificate(cert_pem)
                cert_id = meta["id"]
                print(f"✓ Vorhandenes Zertifikat wiederverwendet ({cert_id})")
        except Exception as e:
            print(f"Cache unbrauchbar: {e}")

    # 2) Otherwise create a new one (and keep below Apple's limit)
    if cert_id is None:
        certs = call("GET", "/certificates", params={"filter[certificateType]": "DISTRIBUTION", "limit": 200})["data"]
        certs.sort(key=lambda c: c["attributes"].get("expirationDate") or "")
        while len(certs) >= 2:
            old = certs.pop(0)
            print(f"Widerrufe altes Zertifikat {old['id']}")
            call("DELETE", f"/certificates/{old['id']}")
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        csr = (x509.CertificateSigningRequestBuilder()
               .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "GitHub CI"),
                                        x509.NameAttribute(NameOID.COUNTRY_NAME, "CH")]))
               .sign(key, hashes.SHA256()))
        csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
        cert = call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": csr_pem}}})["data"]
        cert_id = cert["id"]
        x509_cert = x509.load_der_x509_certificate(base64.b64decode(cert["attributes"]["certificateContent"]))
        if cache_dir:
            os.makedirs(cache_dir, exist_ok=True)
            blob = (key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
                    + b"\n----SPLIT----\n" + x509_cert.public_bytes(serialization.Encoding.PEM))
            open(os.path.join(cache_dir, "cert.enc"), "wb").write(fernet.encrypt(blob))
            json.dump({"id": cert_id}, open(meta_path, "w"))
            with open(os.environ.get("GITHUB_OUTPUT", "/dev/null"), "a") as gh:
                gh.write(f"new_cert={cert_id}\n")

    p12 = pkcs12.serialize_key_and_certificates(b"ci", key, x509_cert, None,
                                                serialization.BestAvailableEncryption(password.encode()))
    with open(os.path.join(out, "dist.p12"), "wb") as f:
        f.write(p12)
    print(f"✓ Zertifikat bereit ({cert_id})")

    profiles = {}
    for identifier in BUNDLE_IDS:
        found = call("GET", "/bundleIds", params={"filter[identifier]": identifier})["data"]
        found = [b for b in found if b["attributes"]["identifier"] == identifier]
        if not found:
            print(f"::warning::Bundle-ID {identifier} fehlt")
            continue
        bid = found[0]["id"]
        name = f"CI {identifier}"
        for p in call("GET", "/profiles", params={"filter[name]": name, "limit": 200})["data"]:
            call("DELETE", f"/profiles/{p['id']}")
        prof = call("POST", "/profiles", {"data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bid}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            }}})["data"]["attributes"]
        with open(os.path.join(out, f"{prof['uuid']}.mobileprovision"), "wb") as f:
            f.write(base64.b64decode(prof["profileContent"]))
        profiles[identifier] = name
        print(f"✓ Profil {name}")

    with open(os.path.join(out, "ExportOptions.plist"), "wb") as f:
        plistlib.dump({
            "method": "app-store-connect",
            "destination": "upload",
            "teamID": os.environ["APPLE_TEAM_ID"],
            "signingStyle": "manual",
            "signingCertificate": "Apple Distribution",
            "provisioningProfiles": profiles,
            "manageAppVersionAndBuildNumber": False,
        }, f)


if __name__ == "__main__":
    main(sys.argv[1])
