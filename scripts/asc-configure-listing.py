#!/usr/bin/env python3
"""Configure the nonlocalized Baby Tracker App Store listing fields."""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402


BUNDLE_ID = "com.jackwallner.baby"
APP_NAME = "Baby Tracker"
# Age-rating answers are copied from a live health app and then overridden
# below. This pointed at the retired Protein Tracker record, so the copy
# would start failing the moment that record went away.
AGE_TEMPLATE_BUNDLE_ID = os.environ.get(
    "ASC_AGE_TEMPLATE_BUNDLE_ID", "com.jackwallner.vitals"
)
# The 4.3 answer, in the order a reviewer meets it: the fresh-install path to
# the first-weeks tally and to a preview of the pediatrician PDF, neither of
# which needs a purchase or days of data.
REVIEW_NOTES = """Baby Tracker is a log for the first months: feeds, wet and dirty diapers, and sleep. There is no account of any kind, so no demo account is needed.

WHAT A FRESH INSTALL SHOWS, WITH NO PURCHASE AND NO DATA
1. One setup screen asks for an optional name and birth date. Tap Start tracking to begin. There is no purchase screen during onboarding.
2. Home: the four log controls. One tap logs at the current time; a long press opens the editor for the time, side, bottle amount or stool colour. Undo sits in a toast for a few seconds. History is the top-left clock button.
3. More (top-right ellipsis) > First Weeks: the diaper tally sheet, with the typical range for each day of life beside each day and the "call your pediatrician if" lines under the table. It renders with no data and with no purchase.
4. More > Pediatrician summary: a full-page preview of the pediatrician PDF. With nothing logged it renders a worked example whose page is stamped "EXAMPLE, NOT YOUR BABY'S DATA" and whose numbers are invented. No reviewer purchase is needed to see it.

FREE, AND STAYING FREE
Logging, the first-weeks tally, full history, both widgets, the Apple Watch app and complication, the Live Activity, partner sharing, and the stain helper.

BABY+ (com.jackwallner.baby.monthly, com.jackwallner.baby.yearly, com.jackwallner.baby.pro.lifetime)
Sharing or exporting the PDF file, the trends charts, CSV export, and more than one baby. Nothing that ships free is locked later.

PARTNER SHARING
CloudKit CKShare between the two parents' own iCloud accounts (private and shared databases). There is no server of ours and no account to create. It needs an iCloud account on the device; without one, logging is unaffected and the rest of the app works.

HEALTH CLAIMS
Diaper and feed counts are presented as typical ranges for healthy full-term newborns, drawn from the American Academy of Pediatrics' parent guidance, with a "call your pediatrician if" list. The app never says normal or abnormal, never assesses or diagnoses, and is not a medical device. The disclaimer appears in onboarding, First Weeks, Summary and More.

PRIVACY
Entries stay on the device and in the user's own iCloud. RevenueCat receives an anonymous app user id, purchase state and coarse purchase-screen interaction counters. No baby names, birth dates or log entries are sent to RevenueCat."""


def review_phone() -> str:
    """The App Review contact number, which never belongs in a public repo.

    Sourced from ASC_REVIEW_PHONE, or from the shell-sourced
    ``~/.baby_credentials`` that the other scripts here already read.
    """
    value = os.environ.get("ASC_REVIEW_PHONE")
    if value:
        return value.strip()
    path = Path.home() / ".baby_credentials"
    if path.exists():
        for line in path.read_text().splitlines():
            key, _, raw = line.partition("=")
            key = key.strip().removeprefix("export ").strip()
            if key == "ASC_REVIEW_PHONE":
                return raw.strip().strip('"').strip("'")
    raise SystemExit(
        "error: set ASC_REVIEW_PHONE, or add it to ~/.baby_credentials.\n"
        "The App Review contact number is deliberately not stored in this repo."
    )


def main() -> None:
    if not REVIEW_NOTES.strip():
        raise SystemExit("error: write REVIEW_NOTES for Baby before configuring the listing")
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    info = A.find_editable_app_info(client, app["id"])
    version = A.find_editable_version(client, app["id"])
    if not info or not version:
        raise SystemExit("error: Baby Tracker needs an editable app info and version")

    client.patch(
        f"/apps/{app['id']}",
        {
            "data": {
                "type": "apps",
                "id": app["id"],
                "attributes": {
                    "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT",
                },
            }
        },
    )
    client.patch(
        f"/appStoreVersions/{version['id']}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version["id"],
                "attributes": {
                    "copyright": "2026 Jack Wallner",
                    "releaseType": "MANUAL",
                },
            }
        },
    )
    age = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    template_app = A.find_app(client, AGE_TEMPLATE_BUNDLE_ID)
    template_info = A.find_editable_app_info(client, template_app["id"])
    template_age = client.get(
        f"/appInfos/{template_info['id']}/ageRatingDeclaration"
    )["data"]["attributes"]
    attrs = {key: value for key, value in template_age.items() if value is not None}
    attrs.pop("ageRatingOverride", None)
    attrs.update(
        {
            "healthOrWellnessTopics": True,
            "medicalOrTreatmentInformation": "NONE",
            "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        }
    )
    client.patch(
        f"/ageRatingDeclarations/{age['id']}",
        {
            "data": {
                "type": "ageRatingDeclarations",
                "id": age["id"],
                "attributes": attrs,
            }
        },
    )

    review = client.get(f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    attributes = {
        "contactFirstName": "Jack",
        "contactLastName": "Wallner",
        "contactPhone": review_phone(),
        "contactEmail": "jackwallner@gmail.com",
        "demoAccountRequired": False,
        "notes": REVIEW_NOTES,
    }
    if review:
        client.patch(
            f"/appStoreReviewDetails/{review['id']}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": review["id"],
                    "attributes": attributes,
                }
            },
        )
    else:
        client.post(
            "/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version["id"]}
                        }
                    },
                }
            },
        )
    print(f"configured {APP_NAME} ({app['id']})")


if __name__ == "__main__":
    main()
