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
REVIEW_NOTES = """Baby Tracker is a log for the first months: feeds, pee and poop diapers, and sleep. There is no account of any kind, so no demo account is needed.

WHAT IS DIFFERENT (GUIDELINE 4.3)
Baby trackers are a crowded category, so this one is deliberately narrow and built for the first weeks: one screen with four controls that never move, no accounts, no ads and no AI. What the category does not offer: (1) First Weeks, the hospital discharge tally sheet as a live table, the parent's logged diapers per day of life beside a sourced, labelled breastfeeding reference; (2) a one-page pediatrician PDF built for the visit, with the longest gap between feeds and weights in the doctor's units; (3) two-parent logging through the parents' own iCloud (CKShare), free, with no account or server; (4) a stain helper for blowouts and spit-up. It is not a template or a reskin. The developer's only other baby app, Baby Docs, is a paperwork planner with no logging of any kind.

WHAT A FRESH INSTALL SHOWS, WITH NO PURCHASE AND NO DATA
1. One setup screen with two paths. Start a new log asks for an optional name and birth date; tap Start tracking. Join a shared log is only for a second parent holding an invite, and can be ignored. There is no purchase screen during onboarding.
2. Home: four log controls, Feed (Left, Right, Bottle), Pee, Poop and Sleep. One tap logs at the current time; a long press opens the editor for the time, side, bottle amount or stool colour. Undo appears at the top for a few seconds. History is the top-left clock button. More > Diaper buttons can rename Pee and Poop to Wet and Dirty.
3. More (top-right ellipsis) > First Weeks: a breastfeeding reference table for the first two weeks, sourced to NHS Healthier Together, beside the counts the parent logged, with the "call your pediatrician if" lines under the table. It renders with no data and with no purchase.
4. More > Pediatrician summary: a full-page preview of the pediatrician PDF. With nothing logged it renders a worked example stamped "EXAMPLE, NOT YOUR BABY'S DATA" whose numbers are invented. No reviewer purchase is needed to see it.

FREE, AND STAYING FREE
Logging, the first-weeks table, full history, both widgets, the Apple Watch app and complication, the Live Activity, logging together, the stain helper, every appearance and more than one baby.

BABY+ (com.jackwallner.baby.monthly, com.jackwallner.baby.yearly, com.jackwallner.baby.pro.lifetime)
Reporting to share with a doctor: sharing or exporting the pediatrician PDF (daily feeds, the longest gap between feeds, wet and dirty counts, sleep, weights and notes), the trends charts, and CSV export. The paywall opens from the locked buttons on the Pediatrician summary page and from More > Baby+. Nothing that ships free is locked later.

LOGGING TOGETHER
More > Log together > Invite someone shows a QR code and a link for a CloudKit CKShare on the baby's record zone, with read/write access. The other parent scans it in the app or opens the link, on their own iCloud account. There is no server of ours and no account to create. It needs iCloud on the device; without it, logging is unaffected and the rest of the app works. It cannot be tested with a single Apple ID.

HEALTH CLAIMS
The First Weeks table is labelled as a breastfeeding reference for the first two weeks, not a target, and the app never assesses the logged counts against it. Fever and feeding links go to the American Academy of Pediatrics' parent site. The app never says normal or abnormal, never diagnoses or treats, and is not a medical device. The disclaimer appears in onboarding, First Weeks, the Pediatrician summary and More.

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
    """`--notes-only` updates the App Review contact and notes and leaves the
    rights, copyright and age rating alone."""
    if not REVIEW_NOTES.strip():
        raise SystemExit("error: write REVIEW_NOTES for Baby before configuring the listing")
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    info = A.find_editable_app_info(client, app["id"])
    version = A.find_editable_version(client, app["id"])
    if not info or not version:
        raise SystemExit("error: Baby Tracker needs an editable app info and version")
    if "--notes-only" not in sys.argv:
        configure_listing(client, app, info, version)
    configure_review(client, version)
    print(f"configured {APP_NAME} ({app['id']})")


def configure_listing(client: A.ASCClient, app: dict, info: dict, version: dict) -> None:

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



def configure_review(client: A.ASCClient, version: dict) -> None:
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


if __name__ == "__main__":
    main()
