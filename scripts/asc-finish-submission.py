#!/usr/bin/env python3
"""Set the remaining public API prerequisite for the first ASC submission."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402


BUNDLE_ID = "com.jackwallner.baby"


def ensure_free_pricing(client: A.ASCClient, app_id: str) -> None:
    schedule = client.get(f"/apps/{app_id}/appPriceSchedule").get("data")
    if schedule:
        try:
            manual = A.list_all(client, f"/appPriceSchedules/{schedule['id']}/manualPrices")
        except RuntimeError as error:
            if "404" not in str(error):
                raise
            manual = []
        if manual:
            print("app price schedule already has manual prices")
            return

    points = A.list_all(client, f"/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=200")
    free = next(
        (point for point in points if float(point["attributes"].get("customerPrice", -1)) == 0.0),
        None,
    )
    if free is None:
        raise SystemExit("error: no free USA app price point")

    client.post(
        "/appPriceSchedules",
        {
            "data": {
                "type": "appPriceSchedules",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": [{"type": "appPrices", "id": "${price0}"}]},
                },
            },
            "included": [
                {
                    "type": "appPrices",
                    "id": "${price0}",
                    "attributes": {"startDate": None},
                    "relationships": {
                        "appPricePoint": {
                            "data": {"type": "appPricePoints", "id": free["id"]}
                        }
                    },
                }
            ],
        },
    )
    print("app price set to free (USA base)")


def main() -> None:
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    client.patch(
        f"/apps/{app['id']}",
        {
            "data": {
                "type": "apps",
                "id": app["id"],
                "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"},
            }
        },
    )
    ensure_free_pricing(client, app["id"])


if __name__ == "__main__":
    main()
