#!/usr/bin/env python3
"""Idempotently create the Baby+ Lifetime non-consumable in App Store Connect.

Extracted from VO2 Max's `asc-setup-release.py`, which also rewrites the app
name, genre, age rating, and review notes. Those belong to a submission pass;
this script does only the IAP, so the paywall has all three products to show in
TestFlight without touching anything submission-related.

Companion to `asc-setup-subscriptions.py`, which creates the monthly and yearly
subscriptions, their free trials, and the PPP price overrides.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE = "com.jackwallner.baby"
PRODUCT_ID = "com.jackwallner.baby.pro.lifetime"
# App Store Connect's internal reference name is immutable after creation.
# The localized customer-facing name is Baby+ Lifetime.
PRODUCT_REFERENCE_NAME = "Baby Plus Lifetime"
PRODUCT_DISPLAY_NAME = "Baby+ Lifetime"
PRODUCT_DESCRIPTION = "Unlock Baby+ forever. One payment."
PRICE = "59.99"

V1 = "https://api.appstoreconnect.apple.com/v1"
V2 = "https://api.appstoreconnect.apple.com/v2"


def main() -> None:
    client = asc_lib.ASCClient.from_credentials()
    app_id = asc_lib.find_app(client, BUNDLE)["id"]
    print(f"app {app_id}")

    territories = [item["id"] for item in asc_lib.list_all(client, "/territories?limit=200")]
    iaps = asc_lib.list_all(client, f"/apps/{app_id}/inAppPurchasesV2")
    iap = next((item for item in iaps if item["attributes"].get("productId") == PRODUCT_ID), None)

    if not iap:
        try:
            asc_lib.API = V2
            iap = client.post(
                "/inAppPurchases",
                {
                    "data": {
                        "type": "inAppPurchases",
                        "attributes": {
                            "name": PRODUCT_REFERENCE_NAME,
                            "productId": PRODUCT_ID,
                            "inAppPurchaseType": "NON_CONSUMABLE",
                            "reviewNote": "One-time purchase that unlocks Baby+ forever.",
                        },
                        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                    }
                },
            )["data"]
        finally:
            asc_lib.API = V1
        print("lifetime IAP created")
    iap_id = iap["id"]

    try:
        asc_lib.API = V2
        existing_locs = asc_lib.list_all(client, f"/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")
    finally:
        asc_lib.API = V1

    locales = ["en-US"]
    by_locale = {item["attributes"].get("locale"): item for item in existing_locs}
    for locale in locales:
        product_path = asc_lib.META / locale / "products.json"
        product = json.loads(product_path.read_text()) if product_path.exists() else {}
        name = product.get("lifetime_name") or PRODUCT_DISPLAY_NAME
        description = product.get("lifetime_desc") or PRODUCT_DESCRIPTION
        existing = by_locale.get(locale)
        if existing:
            attrs = existing.get("attributes", {})
            if attrs.get("name") != name or attrs.get("description") != description:
                client.patch(
                    f"/inAppPurchaseLocalizations/{existing['id']}",
                    {
                        "data": {
                            "type": "inAppPurchaseLocalizations",
                            "id": existing["id"],
                            "attributes": {"name": name, "description": description},
                        }
                    },
                )
            continue
        client.post(
            "/inAppPurchaseLocalizations",
            {
                "data": {
                    "type": "inAppPurchaseLocalizations",
                    "attributes": {"locale": locale, "name": name, "description": description},
                    "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}},
                }
            },
        )
    print(f"IAP localizations set for {len(locales)} locales")

    try:
        asc_lib.API = V2
        client.get(f"/inAppPurchases/{iap_id}/iapPriceSchedule")
        schedule_exists = True
    except RuntimeError:
        schedule_exists = False
    finally:
        asc_lib.API = V1

    try:
        asc_lib.API = V2
        points = asc_lib.list_all(client, f"/inAppPurchases/{iap_id}/pricePoints?filter[territory]=USA&limit=200")
    finally:
        asc_lib.API = V1
    point = next((item for item in points if item["attributes"].get("customerPrice") == PRICE), None)
    if not point:
        raise SystemExit(f"error: USA price point {PRICE} unavailable")
    client.post(
        "/inAppPurchasePriceSchedules",
        {
            "data": {
                "type": "inAppPurchasePriceSchedules",
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price0}"}]},
                },
            },
            "included": [
                {
                    "type": "inAppPurchasePrices",
                    "id": "${price0}",
                    "attributes": {"startDate": None},
                    "relationships": {
                        "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point["id"]}}
                    },
                }
            ],
        },
    )
    print(f"IAP price {'updated' if schedule_exists else 'set'} ${PRICE}")

    try:
        asc_lib.API = V2
        client.get(f"/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
        print("IAP availability exists")
    except RuntimeError:
        asc_lib.API = V1
        client.post(
            "/inAppPurchaseAvailabilities",
            {
                "data": {
                    "type": "inAppPurchaseAvailabilities",
                    "attributes": {"availableInNewTerritories": True},
                    "relationships": {
                        "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                        "availableTerritories": {"data": [{"type": "territories", "id": item} for item in territories]},
                    },
                }
            },
        )
        print(f"IAP available in {len(territories)} territories")
    finally:
        asc_lib.API = V1


if __name__ == "__main__":
    main()
