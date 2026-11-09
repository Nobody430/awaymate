"""Registers bundle IDs and capabilities via the App Store Connect API (idempotent)."""
# Runs on every TestFlight build (idempotent).
# App records exist in App Store Connect since 2026-11-09.
import json
import os
import sys
import time

import jwt
import requests

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
P8 = os.environ["ASC_KEY_P8"]
API = "https://api.appstoreconnect.apple.com/v1"

APPS = [
    ("Skylog", "com.nobody430.skylog", ["APP_GROUPS"]),
    ("Skylog Widgets", "com.nobody430.skylog.widgets", ["APP_GROUPS"]),
    ("Vital", "com.nobody430.vital", ["HEALTHKIT"]),
    ("Saldo", "com.nobody430.saldo", []),
]


def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def call(method, path, body=None, params=None):
    r = requests.request(method, API + path, params=params, json=body,
                         headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}, timeout=30)
    if r.status_code >= 400:
        print(f"::warning::{method} {path} -> {r.status_code}: {r.text[:300]}")
    return r


def main():
    print("Apple-Einrichtung startet …")
    for name, identifier, caps in APPS:
        r = call("GET", "/bundleIds", params={"filter[identifier]": identifier, "include": "bundleIdCapabilities"})
        if r.status_code >= 400:
            sys.exit("API-Schlüssel ungültig oder ohne Admin-Rechte.")
        data = [b for b in r.json().get("data", []) if b["attributes"]["identifier"] == identifier]
        if data:
            bid = data[0]["id"]
            print(f"✓ {identifier} existiert")
        else:
            r = call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {
                "identifier": identifier, "name": name, "platform": "IOS"}}})
            if r.status_code >= 400:
                continue
            bid = r.json()["data"]["id"]
            print(f"+ {identifier} angelegt")
        existing = {c["attributes"]["capabilityType"] for c in
                    call("GET", f"/bundleIds/{bid}/bundleIdCapabilities").json().get("data", [])}
        for cap in caps:
            if cap in existing:
                continue
            r = call("POST", "/bundleIdCapabilities", {"data": {
                "type": "bundleIdCapabilities", "attributes": {"capabilityType": cap},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
            if r.status_code < 400:
                print(f"  + {cap} aktiviert")

    apps = call("GET", "/apps", params={"limit": 200}).json().get("data", [])
    have = {a["attributes"]["bundleId"] for a in apps}
    missing = [i for _, i, _ in APPS if not i.endswith(".widgets") and i not in have]
    if missing:
        print("::warning::Noch in App Store Connect anzulegen (Apps → + → Neue App): " + ", ".join(missing))
    else:
        print("✓ Alle Apps in App Store Connect vorhanden")


if __name__ == "__main__":
    main()
