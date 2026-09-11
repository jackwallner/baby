#!/usr/bin/env python3
"""Fill in subscription prices for every territory from the USA base price.

For each Baby subscription: take its existing USA price point, fetch that
point's equalizations (Apple's suggested equivalent in every other territory),
and create a subscriptionPrice per territory that doesn't have one yet.

Usage: source ~/.baseball_credentials && python3 scripts/asc-equalize-sub-prices.py
"""

import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE = "com.jackwallner.baby"
USA_PRICES = {
    "com.jackwallner.baby.monthly": "5.99",
    "com.jackwallner.baby.yearly": "29.99",
}

# When True, post the equalized price point for EVERY territory (price change);
# when False, only fill territories that have no price yet (initial setup).
REPLACE_EXISTING = False


def main() -> None:
    c = asc_lib.ASCClient.from_credentials()
    app = asc_lib.find_app(c, BUNDLE)
    group = c.get(f"/apps/{app['id']}/subscriptionGroups")["data"][0]

    for sub in c.get(f"/subscriptionGroups/{group['id']}/subscriptions")["data"]:
        pid = sub["attributes"]["productId"]
        if pid not in USA_PRICES:
            continue
        sub_id = sub["id"]

        priced = set()
        d = c.get(f"/subscriptions/{sub_id}/prices?include=territory&limit=200")
        pages = [d]
        while d.get("links", {}).get("next"):
            d = c.get(d["links"]["next"].replace(asc_lib.API, ""))
            pages.append(d)
        for page in pages:
            for inc in page.get("included") or []:
                if inc["type"] == "territories":
                    priced.add(inc["id"])
        print(f"{pid}: {len(priced)} territories already priced")

        points = asc_lib.list_all(
            c, f"/subscriptions/{sub_id}/pricePoints?filter[territory]=USA&limit=200"
        )
        usa_point = next(
            p for p in points if p["attributes"]["customerPrice"] == USA_PRICES[pid]
        )

        eq = asc_lib.list_all(
            c,
            f"/subscriptionPricePoints/{urllib.parse.quote(usa_point['id'], safe='')}"
            "/equalizations?include=territory&limit=200",
        )
        created = 0
        failed = 0
        for point in eq:
            terr = (point.get("relationships", {}).get("territory", {}).get("data") or {}).get("id")
            if not terr:
                continue
            if not REPLACE_EXISTING and terr in priced:
                continue
            try:
                c.post(
                    "/subscriptionPrices",
                    {
                        "data": {
                            "type": "subscriptionPrices",
                            "relationships": {
                                "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                                "subscriptionPricePoint": {
                                    "data": {"type": "subscriptionPricePoints", "id": point["id"]}
                                },
                            },
                        }
                    },
                )
                created += 1
            except RuntimeError as e:
                failed += 1
                print(f"  {terr}: {e}", file=sys.stderr)
        print(f"{pid}: posted {created} territory prices ({failed} failed)")

    print("done")


if __name__ == "__main__":
    main()
