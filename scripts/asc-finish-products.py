#!/usr/bin/env python3
"""Clear MISSING_METADATA on the Baby+ products.

Subscriptions need an availability record (all territories) and an App Review
screenshot; the lifetime non-consumable needs only the screenshot.

Idempotent: existing pieces are skipped.

    python3 scripts/asc-finish-products.py --screenshot path/to/shot.png
"""
from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE = "com.jackwallner.baby"


def all_territories(c: asc_lib.ASCClient) -> list[str]:
    return [t["id"] for t in asc_lib.list_all(c, "/territories?limit=200")]


def ensure_sub_availability(c: asc_lib.ASCClient, sub_id: str, territories: list[str]) -> str:
    existing = c.get(f"/subscriptions/{sub_id}/subscriptionAvailability")
    if existing.get("data"):
        return "already set"
    c.post(
        "/subscriptionAvailabilities",
        {
            "data": {
                "type": "subscriptionAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                    "availableTerritories": {
                        "data": [{"type": "territories", "id": t} for t in territories]
                    },
                },
            }
        },
    )
    return f"created ({len(territories)} territories)"


def iap_screenshot(c: asc_lib.ASCClient, iap_id: str) -> dict | None:
    """The IAP screenshot relationship only reads back on the v2 resource path."""
    url = f"https://api.appstoreconnect.apple.com/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {c.token}"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        import json

        return json.loads(resp.read().decode()).get("data")


def upload_asset(c: asc_lib.ASCClient, res_type: str, rel_key: str, rel_type: str,
                 parent_id: str, png: Path) -> str:
    blob = png.read_bytes()
    created = c.post(
        f"/{res_type}",
        {
            "data": {
                "type": res_type,
                "attributes": {"fileSize": len(blob), "fileName": png.name},
                "relationships": {rel_key: {"data": {"type": rel_type, "id": parent_id}}},
            }
        },
    )["data"]
    for op in created["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"]: op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req, timeout=300).read()
    c.patch(
        f"/{res_type}/{created['id']}",
        {
            "data": {
                "type": res_type,
                "id": created["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }
        },
    )
    return "uploaded"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--screenshot", required=True, help="PNG shown to App Review for each product")
    ap.add_argument(
        "--replace",
        action="store_true",
        help="replace an existing App Review screenshot with this file",
    )
    args = ap.parse_args()
    png = Path(args.screenshot)
    if not png.is_file():
        raise SystemExit(f"error: no such screenshot: {png}")

    c = asc_lib.ASCClient.from_credentials()
    app_id = asc_lib.find_app(c, BUNDLE)["id"]
    territories = all_territories(c)

    groups = asc_lib.list_all(c, f"/apps/{app_id}/subscriptionGroups")
    for g in groups:
        for sub in asc_lib.list_all(c, f"/subscriptionGroups/{g['id']}/subscriptions"):
            sid, pid = sub["id"], sub["attributes"]["productId"]
            print(f"{pid}: availability {ensure_sub_availability(c, sid, territories)}")
            existing = c.get(f"/subscriptions/{sid}/appStoreReviewScreenshot").get("data")
            if existing and args.replace:
                c.delete(f"/subscriptionAppStoreReviewScreenshots/{existing['id']}")
                print(f"{pid}: removed stale screenshot")
                existing = None
            if existing:
                print(f"{pid}: screenshot already set")
            else:
                print(f"{pid}: screenshot {upload_asset(c, 'subscriptionAppStoreReviewScreenshots', 'subscription', 'subscriptions', sid, png)}")

    for iap in asc_lib.list_all(c, f"/apps/{app_id}/inAppPurchasesV2"):
        iid, pid = iap["id"], iap["attributes"]["productId"]
        existing = iap_screenshot(c, iid)
        if existing and args.replace:
            c.delete(f"/inAppPurchaseAppStoreReviewScreenshots/{existing['id']}")
            print(f"{pid}: removed stale screenshot")
            existing = None
        if existing:
            print(f"{pid}: screenshot already set")
        else:
            print(f"{pid}: screenshot {upload_asset(c, 'inAppPurchaseAppStoreReviewScreenshots', 'inAppPurchaseV2', 'inAppPurchases', iid, png)}")

    print("\nStates now:")
    for g in groups:
        for sub in asc_lib.list_all(c, f"/subscriptionGroups/{g['id']}/subscriptions"):
            print(f"  {sub['attributes']['productId']}: {sub['attributes']['state']}")
    for iap in asc_lib.list_all(c, f"/apps/{app_id}/inAppPurchasesV2"):
        print(f"  {iap['attributes']['productId']}: {iap['attributes']['state']}")


if __name__ == "__main__":
    main()
