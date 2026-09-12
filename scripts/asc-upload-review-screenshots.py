#!/usr/bin/env python3
"""Attach one App Review screenshot per Baby+ product.

Each product's screenshot has to show that product's own billed amount, so the
three renders from `BabyUITests/PaywallScreenshotUITests` go to the three
products rather than one image going to all of them.

    python3 scripts/asc-upload-review-screenshots.py --dir build/paywall-shots

Idempotent by default: an existing screenshot is left alone unless --replace.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE = "com.jackwallner.baby"
# product id suffix -> render filename
SHOTS = {
    "monthly": "paywall-monthly.png",
    "yearly": "paywall-yearly.png",
    "pro.lifetime": "paywall-lifetime.png",
}


def all_territories(c: asc_lib.ASCClient) -> list[str]:
    return [t["id"] for t in asc_lib.list_all(c, "/territories?limit=200")]


def ensure_sub_availability(c: asc_lib.ASCClient, sub_id: str, territories: list[str]) -> str:
    if c.get(f"/subscriptions/{sub_id}/subscriptionAvailability").get("data"):
        return "already set"
    c.post(
        "/subscriptionAvailabilities",
        {
            "data": {
                "type": "subscriptionAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                    "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]},
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
        return json.loads(resp.read().decode()).get("data")


def upload(c: asc_lib.ASCClient, res_type: str, rel_key: str, rel_type: str, parent_id: str, png: Path) -> str:
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
        request = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for header in op["requestHeaders"]:
            request.add_header(header["name"], header["value"])
        urllib.request.urlopen(request, timeout=300).read()
    c.patch(
        f"/{res_type}/{created['id']}",
        {
            "data": {
                "type": res_type,
                "id": created["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()},
            }
        },
    )
    return f"uploaded {png.name}"


def shot_for(product_id: str, folder: Path) -> Path | None:
    for suffix, filename in SHOTS.items():
        if product_id.endswith(f".{suffix}"):
            path = folder / filename
            return path if path.is_file() else None
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default="build/paywall-shots", help="folder holding the three renders")
    parser.add_argument("--replace", action="store_true", help="replace an existing App Review screenshot")
    args = parser.parse_args()
    folder = Path(args.dir)

    c = asc_lib.ASCClient.from_credentials()
    app_id = asc_lib.find_app(c, BUNDLE)["id"]
    territories = all_territories(c)

    for group in asc_lib.list_all(c, f"/apps/{app_id}/subscriptionGroups"):
        for sub in asc_lib.list_all(c, f"/subscriptionGroups/{group['id']}/subscriptions"):
            sid, pid = sub["id"], sub["attributes"]["productId"]
            png = shot_for(pid, folder)
            if png is None:
                print(f"{pid}: no render found, skipped")
                continue
            print(f"{pid}: availability {ensure_sub_availability(c, sid, territories)}")
            existing = c.get(f"/subscriptions/{sid}/appStoreReviewScreenshot").get("data")
            if existing and args.replace:
                c.delete(f"/subscriptionAppStoreReviewScreenshots/{existing['id']}")
                existing = None
                print(f"{pid}: removed the previous screenshot")
            if existing:
                print(f"{pid}: screenshot already set")
            else:
                print(f"{pid}: {upload(c, 'subscriptionAppStoreReviewScreenshots', 'subscription', 'subscriptions', sid, png)}")

    for iap in asc_lib.list_all(c, f"/apps/{app_id}/inAppPurchasesV2"):
        iid, pid = iap["id"], iap["attributes"]["productId"]
        png = shot_for(pid, folder)
        if png is None:
            print(f"{pid}: no render found, skipped")
            continue
        existing = iap_screenshot(c, iid)
        if existing and args.replace:
            c.delete(f"/inAppPurchaseAppStoreReviewScreenshots/{existing['id']}")
            existing = None
            print(f"{pid}: removed the previous screenshot")
        if existing:
            print(f"{pid}: screenshot already set")
        else:
            print(f"{pid}: {upload(c, 'inAppPurchaseAppStoreReviewScreenshots', 'inAppPurchaseV2', 'inAppPurchases', iid, png)}")

    print("\nStates now:")
    for group in asc_lib.list_all(c, f"/apps/{app_id}/subscriptionGroups"):
        for sub in asc_lib.list_all(c, f"/subscriptionGroups/{group['id']}/subscriptions"):
            print(f"  {sub['attributes']['productId']}: {sub['attributes']['state']}")
    for iap in asc_lib.list_all(c, f"/apps/{app_id}/inAppPurchasesV2"):
        print(f"  {iap['attributes']['productId']}: {iap['attributes']['state']}")


if __name__ == "__main__":
    main()
