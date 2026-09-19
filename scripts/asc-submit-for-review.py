#!/usr/bin/env python3
"""Add the draft version to the staged review submission and submit it.

The last step of a release, and the one nothing else in this repo does. It is
deliberately two operations in one script because they only make sense
together: a review submission with no items submits nothing, and an item added
to a submission that is never submitted just freezes the metadata it points at
(see CLAUDE.md, "ASC submission freezes IAP metadata").

Products (subscriptions and one-time IAPs) cannot be added here. The v1
`reviewSubmissionItems` endpoint this API key can see has no relationship for
them, so they are queued by hand in Monetization > Add for Review. This script
reports how many items the submission already carries so a missing product is
visible before the submit rather than after the review.

    scripts/asc-submit-for-review.py --dry-run   # report, change nothing
    scripts/asc-submit-for-review.py             # add the version, submit
"""

from __future__ import annotations

import argparse
import base64
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asc_lib as a  # noqa: E402

BUNDLE_ID = "com.jackwallner.baby"
EXPECTED_ITEMS = 5


def item_parts(item_id: str) -> list[str]:
    padded = item_id + "=" * (-len(item_id) % 4)
    try:
        return base64.b64decode(padded).decode().split("|")
    except Exception:
        return []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    client = a.ASCClient.from_credentials()
    app_id = a.find_app(client, BUNDLE_ID)["id"]

    version = a.find_editable_version(client, app_id)
    if version is None:
        version = next(
            (
                candidate
                for candidate in a.list_versions(client, app_id)
                if candidate.get("attributes", {}).get("appStoreState") == "READY_FOR_REVIEW"
            ),
            None,
        )
    if version is None:
        print("No editable or READY_FOR_REVIEW version. Nothing to submit.")
        return 1
    version_id = version["id"]
    attrs = version["attributes"]
    print(f"version {attrs['versionString']} ({attrs['appStoreState']})")

    build = client.get(f"/appStoreVersions/{version_id}/build").get("data")
    if build is None:
        print("FAIL: no build attached. Run scripts/asc-attach-build.py first.")
        return 1
    print(f"attached build {build['attributes']['version']} ({build['attributes']['processingState']})")

    submissions = a.list_all(client, f"/apps/{app_id}/reviewSubmissions?filter[platform]=IOS")
    open_submissions = [s for s in submissions if s["attributes"]["state"] == "READY_FOR_REVIEW"]
    if not open_submissions:
        states = ", ".join(sorted({s["attributes"]["state"] for s in submissions})) or "none"
        print(f"No READY_FOR_REVIEW submission to submit (states: {states}).")
        return 1
    submission = open_submissions[0]
    submission_id = submission["id"]

    items = a.list_all(client, f"/reviewSubmissions/{submission_id}/items")
    types = [item_parts(item["id"])[1] if len(item_parts(item["id"])) > 2 else "?" for item in items]
    print(f"submission {submission_id}: {len(items)} item(s), types {types}")

    # The items come back with every relationship empty for this key, and the
    # type digit in the id is not a reliable tell: a submission holding the
    # three products reported a type the version was assumed to use, the add
    # was skipped, and the submit failed on a missing appStoreVersionForReview.
    # So the add is always attempted and a duplicate is treated as success.
    if args.dry_run:
        print("would add the version as a review submission item (duplicate is fine)")
    else:
        try:
            client.post(
                "/reviewSubmissionItems",
                {
                    "data": {
                        "type": "reviewSubmissionItems",
                        "relationships": {
                            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                            "reviewSubmission": {
                                "data": {"type": "reviewSubmissions", "id": submission_id}
                            },
                        },
                    }
                },
            )
            print("added the version to the submission")
        except RuntimeError as error:
            # A version already in the submission answers DUPLICATE or, once
            # the products sit beside it, RELATIONSHIP.INVALID.NOT_ALLOWED.
            if "DUPLICATE" not in str(error) and "NOT_ALLOWED" not in str(error):
                raise
            print("version was already queued")

    items = a.list_all(client, f"/reviewSubmissions/{submission_id}/items")
    if len(items) != EXPECTED_ITEMS:
        print(
            f"FAIL: expected {EXPECTED_ITEMS} review items (version, subscription group, "
            f"monthly, yearly, lifetime), found {len(items)}."
        )
        return 1

    if args.dry_run:
        print("dry run: not submitting")
        return 0

    client.patch(
        f"/reviewSubmissions/{submission_id}",
        {"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}},
    )
    after = client.get(f"/reviewSubmissions/{submission_id}")["data"]["attributes"]
    print(f"submitted: state={after['state']} submittedDate={after.get('submittedDate')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
