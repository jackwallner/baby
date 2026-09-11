#!/usr/bin/env python3
"""Report what the App Store Connect record still needs before submission.

Read-only. Run it before a submission pass to see the gaps rather than
discovering them in the ASC web UI one blocked field at a time.

    python3 scripts/asc-readiness.py

Note on paths: `asc_lib.API` already ends in `/v1`, so every path passed to the
client must start at the resource (`/builds`, not `/v1/builds`).

Two things this script cannot see, because Apple does not expose them in the
App Store Connect API at all:

  * the **Regulated Medical Device** declaration (App Review 1.4.1), which is
    web-UI only. Baby Tracker answers No: it tracks a number the user or
    their clinician set and makes no diagnostic or treatment claim.
  * whether the privacy/support/marketing URLs actually resolve. This script
    fetches them, because App Review rejects on a dead privacy URL and the
    fleet convention of serving them from the repo's own GitHub Pages means
    they 404 until that repo exists and is public.
"""
from __future__ import annotations

import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402

BUNDLE_ID = "com.jackwallner.baby"
EXPECTED_NAME = "Baby Tracker"
EXPECTED_CATEGORY = "HEALTH_AND_FITNESS"
DENSE_SCRIPT_LOCALES = {"ja", "ko", "zh-Hans", "zh-Hant"}
EXPECTED_SCREENSHOTS_BY_TYPE = {
    "APP_IPHONE_67": 6,
    "APP_WATCH_SERIES_10": 1,
}
EXPECTED_INTRO_OFFERS = 175

ready: list[str] = []
gaps: list[str] = []


def check(label: str, value, good: bool | None = None) -> None:
    good = bool(value) if good is None else good
    (ready if good else gaps).append(f"{label}: {value}")


def url_status(url: str) -> str:
    try:
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=20) as response:
            return str(response.status)
    except urllib.error.HTTPError as error:
        return str(error.code)
    except Exception as error:  # noqa: BLE001 - any network failure is a gap
        return type(error).__name__


def main() -> None:
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    info = A.find_editable_app_info(client, app["id"])
    version = A.find_editable_version(client, app["id"])

    info_localizations = A.list_all(client, f"/appInfos/{info['id']}/appInfoLocalizations")
    primary = next((item for item in info_localizations if item["attributes"]["locale"] == "en-US"), None)
    name = primary["attributes"].get("name") if primary else None
    check("app record name", name, name == EXPECTED_NAME)

    category = client.get(f"/appInfos/{info['id']}/primaryCategory").get("data")
    check(
        "primary category",
        category and category["id"],
        bool(category) and category["id"] == EXPECTED_CATEGORY,
    )
    copyright_text = version["attributes"].get("copyright")
    check("copyright", copyright_text)

    urls: set[str] = set()
    gaps_by_field: dict[str, list[str]] = {}

    def fails(field: str, locale: str, detail: str = "") -> None:
        gaps_by_field.setdefault(field, []).append(f"{locale}{f' {detail}' if detail else ''}")

    def report(field: str, total: int) -> None:
        bad = gaps_by_field.get(field, [])
        check(field, f"{total} locales" if not bad else f"{len(bad)} bad: {', '.join(bad[:6])}", not bad)

    for localization in info_localizations:
        attributes = localization["attributes"]
        locale = attributes["locale"]
        localized_name = attributes.get("name") or ""
        subtitle = attributes.get("subtitle") or ""
        # Apple's cap is 30 everywhere, but the 24-character floor is a
        # Latin-script rule: it stops a name wasting the field on a few short
        # words. Chinese, Japanese, and Korean carry a word in one or two
        # characters, so holding them to 24 forces padding a finished name with
        # filler that reads worse and ranks no better. Those keep the ceiling.
        minimum = 10 if locale in DENSE_SCRIPT_LOCALES else 24
        if not minimum <= len(localized_name) <= 30:
            fails("name 24-30 chars", locale, str(len(localized_name)))
        if not minimum <= len(subtitle) <= 30:
            fails("subtitle 24-30 chars", locale, str(len(subtitle)))
        privacy = attributes.get("privacyPolicyUrl")
        if privacy:
            urls.add(privacy)
        else:
            fails("privacy url", locale)
    for field in ("name 24-30 chars", "subtitle 24-30 chars", "privacy url"):
        report(field, len(info_localizations))

    version_localizations = A.list_all(
        client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations"
    )
    for localization in version_localizations:
        attributes = localization["attributes"]
        locale = attributes["locale"]
        description = attributes.get("description") or ""
        keywords = attributes.get("keywords") or ""
        if len(description) <= 200:
            fails("description", locale, str(len(description)))
        if re.search(r"[$€£¥₹]\s*\d", description):
            fails("description has no hardcoded price", locale)
        # Apple wants the auto-renew terms in the description of every
        # storefront, in that storefront's language, so only the English
        # locales can be checked phrase by phrase. Everywhere else, assert the
        # parts that survive translation: the 24-hour clause and both links.
        if locale.startswith("en"):
            required = ("24 hours", "Privacy Policy", "Terms of Use")
            # "Subscriptions renew automatically" and "Each subscription renews
            # automatically" are the same disclosure; only the verb agreement
            # differs with the subject, so match the stem.
            renewal = "renew automatically" in description
        else:
            required = ("stdeula", "privacy-policy.html")
            # The renewal window is written in the storefront's own digits, and
            # Bengali writes 24 as \u09e8\u09ea, so match any script's numerals.
            renewal = re.search(r"[0-9\u0660-\u0669\u06f0-\u06f9\u0966-\u096f"
                                r"\u09e6-\u09ef\u0a66-\u0a6f\u0ae6-\u0aef"
                                r"\u0b66-\u0b6f\u0be6-\u0bef\u0c66-\u0c6f"
                                r"\u0ce6-\u0cef\u0d66-\u0d6f\u0e50-\u0e59]{2}",
                                description) is not None
        if not renewal or not all(term in description for term in required):
            fails("subscription disclosure", locale)
        # Same script-dependence as the name and subtitle floor above. A
        # Japanese or Chinese keyword is one or two characters, so 94 of them
        # is several times the term list the field is meant to hold, and the
        # floor can only be met by padding with terms nobody searches.
        keyword_floor = 0 if locale in DENSE_SCRIPT_LOCALES else 94
        if not keyword_floor <= len(keywords) <= 100:
            fails("keywords 94-100 chars", locale, str(len(keywords)))
        for field in ("supportUrl", "marketingUrl"):
            value = attributes.get(field)
            if value:
                urls.add(value)
            else:
                fails(field, locale)
        for screenshot_set in A.list_all(
            client, f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets"
        ):
            images = A.list_all(
                client, f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots"
            )
            display_type = screenshot_set["attributes"].get("screenshotDisplayType")
            # A fastlane retry can double-upload, so assert the exact count
            # rather than merely "some screenshots exist".
            expected_screenshots = EXPECTED_SCREENSHOTS_BY_TYPE.get(display_type, 4)
            check(
                f"screenshots {display_type} ({locale})",
                len(images),
                len(images) == expected_screenshots,
            )
    for field in ("description", "description has no hardcoded price", "subscription disclosure",
                  "keywords 94-100 chars", "supportUrl", "marketingUrl"):
        report(field, len(version_localizations))

    declaration = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]["attributes"]
    check(
        "age rating",
        f"wellness={declaration.get('healthOrWellnessTopics')} "
        f"medical={declaration.get('medicalOrTreatmentInformation')}",
        declaration.get("healthOrWellnessTopics") is True,
    )

    review_detail = client.get(
        f"/appStoreVersions/{version['id']}/appStoreReviewDetail"
    ).get("data")
    check("review detail", "present" if review_detail else None)
    if review_detail:
        review_attributes = review_detail["attributes"]
        for field in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
            check(f"review {field}", "present" if review_attributes.get(field) else None)
        review_notes = (review_attributes.get("notes") or "").lower()
        # The notes have to tell the reviewer that the distinguishing feature
        # is reachable without buying anything. Assert the claim rather than a
        # heading: the heading was "LOGGING IS FREE" until the cutoff became
        # the thing a reviewer most needs to reach, and a check pinned to the
        # old wording reported the rewritten notes as stale.
        states_free_access = "no reviewer purchase is needed" in review_notes
        check(
            "review notes state the feature needs no purchase",
            "current" if states_free_access else "stale",
            states_free_access,
        )

    # Paid-product review notes sit beside the app review notes in Apple's
    # queue. They must describe the same free/paid split as the binary.
    groups = A.list_all(client, f"/apps/{app['id']}/subscriptionGroups")
    for group in groups:
        for subscription in A.list_all(client, f"/subscriptionGroups/{group['id']}/subscriptions"):
            attributes = subscription["attributes"]
            product_id = attributes.get("productId") or subscription["id"]
            subscription_id = subscription["id"]
            state = attributes.get("state")
            localizations = A.list_all(
                client,
                f"/subscriptions/{subscription_id}/subscriptionLocalizations",
            )
            prices = A.list_all(
                client,
                f"/subscriptions/{subscription_id}/prices?filter[territory]=USA&limit=200",
            )
            try:
                availability = client.get(
                    f"/subscriptions/{subscription_id}/subscriptionAvailability"
                ).get("data")
            except RuntimeError:
                availability = None
            try:
                screenshot = client.get(
                    f"/subscriptions/{subscription_id}/appStoreReviewScreenshot"
                ).get("data")
            except RuntimeError:
                screenshot = None
            screenshot_state = (
                (screenshot or {}).get("attributes", {})
                .get("assetDeliveryState", {})
                .get("state")
            )
            fields_complete = bool(localizations and prices and availability) and screenshot_state == "COMPLETE"
            subscription_ready = state == "READY_TO_SUBMIT" or (
                state == "MISSING_METADATA" and fields_complete
            )
            displayed_state = (
                "PREPARE_FOR_SUBMISSION (verified fields)"
                if subscription_ready and state == "MISSING_METADATA"
                else state
            )
            check(
                f"subscription {product_id}",
                displayed_state,
                subscription_ready,
            )
            note = attributes.get("reviewNote") or ""
            stale_terms = ("wrist logging", "30-day history", "30 day history")
            check(
                f"subscription note {product_id}",
                "current" if note and not any(term in note.lower() for term in stale_terms) else "stale",
                bool(note) and not any(term in note.lower() for term in stale_terms),
            )
            offers = A.list_all(
                client,
                f"/subscriptions/{subscription_id}/introductoryOffers?limit=200",
            )
            check(
                f"subscription trial territories {product_id}",
                len(offers),
                len(offers) == EXPECTED_INTRO_OFFERS,
            )

    for purchase in A.list_all(client, f"/apps/{app['id']}/inAppPurchasesV2"):
        attributes = purchase["attributes"]
        product_id = attributes.get("productId") or purchase["id"]
        check(
            f"in-app purchase {product_id}",
            attributes.get("state"),
            attributes.get("state") == "READY_TO_SUBMIT",
        )

    # Which build, not just whether one is attached. A draft version keeps
    # whatever build was attached first, so an app that has uploaded ten more
    # since then still reports "a build is attached" while pointing at a binary
    # that predates the product. Build 8 sat on the 1.0 draft for two days
    # after logging went free, so the description promised a free tap the
    # attached binary charged for.
    build = client.get(f"/appStoreVersions/{version['id']}/build").get("data")
    attached_version = build["attributes"].get("version") if build else None
    check("attached build", attached_version)
    if attached_version:
        newest = max(
            (
                b["attributes"]["version"]
                for b in A.list_all(client, f"/builds?filter[app]={app['id']}&limit=200")
                if b["attributes"].get("processingState") == "VALID"
                and not b["attributes"].get("expired")
            ),
            key=lambda v: int(v) if v.isdigit() else -1,
            default=None,
        )
        check(
            "attached build is the newest VALID build",
            f"attached {attached_version}, newest {newest}",
            attached_version == newest,
        )

    print("READY:")
    for line in ready:
        print("  +", line)
    print("\nGAPS:")
    for line in gaps:
        print("  -", line)
    if not gaps:
        print("  (none)")

    print("\nURL REACHABILITY (App Review rejects on a dead privacy URL):")
    for url in sorted(urls):
        status = url_status(url)
        marker = "+" if status == "200" else "-"
        print(f"  {marker} {status}  {url}")

    print("\nNOT VISIBLE TO THE API, CHECK BY HAND IN APP STORE CONNECT:")
    print("  * Regulated Medical Device declaration -> answer No")
    print("  * RevenueCat 'default' offering must have 3 packages "
          "(scripts/rc-setup.py)")


if __name__ == "__main__":
    main()
