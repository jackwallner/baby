#!/usr/bin/env python3
"""Make every customer-visible product name say "Baby+", not "Baby Plus".

`asc-setup-subscriptions.py` and `asc-setup-lifetime-iap.py` seeded all 50
locales from their reference names, which spell the tier out, and only en-US was
hand-corrected afterwards. The other 49 locales therefore showed "Baby Plus
Monthly" in the App Store purchase sheet and in Settings › Apple ID ›
Subscriptions, while the app, the paywall, the website, and the App Store
description all say Baby+.

Idempotent: it only patches localizations whose name still contains the spelled
out form. Reference names (ASC-internal) are left alone.

    python3 scripts/asc-rename-plus-branding.py [--dry-run]
"""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402

BUNDLE_ID = "com.jackwallner.baby"
SPELLED_OUT = "Baby Plus"
BRANDED = "Baby+"

V2 = "https://api.appstoreconnect.apple.com/v2"


def v2_get(client: A.ASCClient, path: str) -> dict:
    """IAP localizations only exist under /v2; `asc_lib.API` ends in /v1."""
    request = urllib.request.Request(
        V2 + path, headers={"Authorization": f"Bearer {client.token}"}
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


def rename(client: A.ASCClient, kind: str, localizations: list[dict], dry_run: bool) -> int:
    changed = 0
    for localization in localizations:
        attributes = localization["attributes"]
        name = attributes["name"]
        if SPELLED_OUT not in name:
            continue
        new_name = name.replace(SPELLED_OUT, BRANDED)
        print(f"  {attributes['locale']}: {name} -> {new_name}")
        if not dry_run:
            client.patch(
                f"/{kind}/{localization['id']}",
                {"data": {"type": kind, "id": localization["id"],
                          "attributes": {"name": new_name}}},
            )
        changed += 1
    return changed


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    client = A.ASCClient.from_credentials()
    app_id = A.find_app(client, BUNDLE_ID)["id"]
    changed = 0

    for group in client.get(f"/apps/{app_id}/subscriptionGroups?limit=20")["data"]:
        print("subscription group", group["attributes"]["referenceName"])
        changed += rename(
            client,
            "subscriptionGroupLocalizations",
            client.get(
                f"/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations?limit=200"
            )["data"],
            dry_run,
        )
        for subscription in client.get(
            f"/subscriptionGroups/{group['id']}/subscriptions?limit=20"
        )["data"]:
            print("subscription", subscription["attributes"]["productId"])
            changed += rename(
                client,
                "subscriptionLocalizations",
                client.get(
                    f"/subscriptions/{subscription['id']}/subscriptionLocalizations?limit=200"
                )["data"],
                dry_run,
            )

    for product in client.get(f"/apps/{app_id}/inAppPurchasesV2?limit=20")["data"]:
        print("in-app purchase", product["attributes"]["productId"])
        changed += rename(
            client,
            "inAppPurchaseLocalizations",
            v2_get(client, f"/inAppPurchases/{product['id']}/inAppPurchaseLocalizations?limit=200")["data"],
            dry_run,
        )

    print(f"\n{'would rename' if dry_run else 'renamed'}: {changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
