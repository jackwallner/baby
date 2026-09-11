#!/usr/bin/env python3
"""Register Baby Tracker bundle IDs and enable their required capabilities."""
from __future__ import annotations

import urllib.parse

import asc_lib


IDENTIFIERS = {
    # iCloud carries partner sharing (CloudKit); push lets CloudKit deliver
    # changes from the other parent's phone. No HealthKit: it has no infant types.
    "com.jackwallner.baby": ("Baby Tracker", {"APP_GROUPS", "IN_APP_PURCHASE", "ICLOUD", "PUSH_NOTIFICATIONS"}),
    "com.jackwallner.baby.widget": ("Baby Tracker Widget", {"APP_GROUPS"}),
    "com.jackwallner.baby.watch": ("Baby Tracker Watch", {"APP_GROUPS", "ICLOUD"}),
    "com.jackwallner.baby.watch.widget": ("Baby Tracker Watch Widget", {"APP_GROUPS"}),
}

# ICLOUD is rejected without its version setting; the others take none.
CAPABILITY_SETTINGS = {
    "ICLOUD": [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6", "enabled": True}]}],
}


def ensure_bundle_id(client: asc_lib.ASCClient, identifier: str, name: str) -> dict:
    quoted = urllib.parse.quote(identifier, safe="")
    found = client.get(f"/bundleIds?filter[identifier]={quoted}").get("data", [])
    if found:
        print(f"bundle id exists: {identifier}")
        return found[0]
    created = client.post(
        "/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": identifier,
                    "name": name,
                    "platform": "IOS",
                },
            }
        },
    )["data"]
    print(f"bundle id created: {identifier}")
    return created


def ensure_capabilities(
    client: asc_lib.ASCClient,
    bundle_id: dict,
    required: set[str],
) -> None:
    bundle_id_id = bundle_id["id"]
    existing = asc_lib.list_all(client, f"/bundleIds/{bundle_id_id}/bundleIdCapabilities")
    enabled = {item["attributes"]["capabilityType"] for item in existing}
    for capability in sorted(required - enabled):
        client.post(
            "/bundleIdCapabilities",
            {
                "data": {
                    "type": "bundleIdCapabilities",
                    "attributes": {"capabilityType": capability, **({"settings": CAPABILITY_SETTINGS[capability]} if capability in CAPABILITY_SETTINGS else {})},
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bundle_id_id}}
                    },
                }
            },
        )
        print(f"  enabled {capability}")


def main() -> None:
    client = asc_lib.ASCClient.from_credentials()
    for identifier, (name, capabilities) in IDENTIFIERS.items():
        bundle_id = ensure_bundle_id(client, identifier, name)
        ensure_capabilities(client, bundle_id, capabilities)


if __name__ == "__main__":
    main()
