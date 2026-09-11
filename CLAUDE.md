# Baby Tracker (working name)

A baby tracker for the first months: one tap to log a feed, a wet or dirty
diaper, or sleep, and one glance to answer "when did she last eat, and which
side". XcodeGen project and scheme: `Baby`. Simulator lease owners: `baby` and
`baby-watch`.

## Status (2026-09-11)

**Not built.** This repo is the Caffeine Tracker chassis, copied and renamed,
plus the research and fleet context for the build. The product described below
does not exist in code yet.

- Copied from `~/caffeine` at `7baa2f9` (tracked files only), then a mechanical
  rename: `Caffeine` to `Baby` in every path, type, bundle id, App Group,
  product id and string. `HKQuantityType(.dietaryCaffeine)` is the one
  identifier left alone because it is a HealthKit API.
- These scripts came from `~/daylight` at `48d0560` instead, because Daylight
  carries the later fixes (retry/backoff in `asc_lib.py`, `--replace` review
  screenshots, the review phone read from `~/.baby_credentials`):
  `asc_lib.py`, `asc-attach-build.py`, `asc-configure-listing.py`,
  `asc-dedupe-screenshots.py`, `asc-equalize-sub-prices.py`,
  `asc-finish-products.py`, `asc-finish-submission.py`,
  `asc-register-identifiers.py`, `asc-rename-plus-branding.py`,
  `asc-setup-lifetime-iap.py`, `asc-setup-subscriptions.py`,
  `asc-submit-for-review.py`, `asc-upload-metadata.py`, `rc-setup.py`,
  `testflight.sh`, `upload-testflight.sh`. `asc-readiness.py` and
  `asc-upload-localizations.py` stayed Caffeine's (newer there).
- The renamed chassis compiles and its 51 tests pass on a leased simulator.
  Those tests are Caffeine's half-life and paywall-funnel tests under new names.
- Removed in the copy: Caffeine's 49 non-English locales, its screenshots, its
  4.3 repositioning script and strings, and its market research. The en-US
  store copy files are emptied, except `name.txt`.
- `docs/` pages are rewritten as an honest pre-release holding page for this
  app. Re-verify the privacy policy against what actually ships.

## Read first

Items marked (local) are gitignored because this repo is public: they carry
personal dates and fleet revenue figures. They exist on this Mac only.

1. `marketreport.md` (local): the verdict, demand, competition, the #1 app's revolt,
   the product angle (free capture, optional reporting, never list), pricing,
   positioning, channels, risks. **This is the brief.**
2. `research/idea-screen-2026-09-11.md` (local): the fleet idea screen that led here.
3. `research/data/`: raw baby screen output (`baby-screen-2026-09-11-raw.txt`, local) (autocomplete, crowding, Astro
   popularity, review themes, price ladders), and the scripts that produced it.
4. `aso-plan.md`: keyword table, name and subtitle candidates, screenshot story.
5. `research/donor-docs/`: `caffeine-CLAUDE.md` (the donor's full guide, the
   4.3 story and the onboarding and paywall rules this chassis encodes),
   `babydocs-CLAUDE.md` and `babydocs-design.md` + `babydocs-design-audit.py`
   (the sibling newborn app: one-time purchase reasoning, why CloudKit `CKShare`
   rather than a server, an enforced design system), and the fleet playbooks
   `current-paywall-playbook.md`, `trial-conversion-thumb-zone.md`,
   `simulator-testing.md` (canonical copies live in `~/ios/`).
6. `research/donor-code/`: fleet code this app needs and Caffeine lacks, not
   compiled. `simpleglp-widget-intent/` is a one-tap log button in a widget via
   `AppIntent`. `posture-live-activity/` is an ActivityKit Live Activity and the
   controller that starts, updates and ends it.

## Product (from marketreport.md)

- **Free forever, capture:** four buttons, Feed (left, right, bottle), Wet,
  Dirty, Sleep. One tap logs now, long press edits, undo toast, no confirmation
  sheets. Now card: "Fed 2h 14m ago, Left", "Last diaper 48m ago". For the first
  two weeks the home screen is the hospital tally sheet: today's wet and dirty
  counts against the typical range for this day of life. Lock screen and home
  widgets, Live Activity for a running feed or sleep, Watch complication, Action
  Button and Siri. Partner sync through iCloud sharing, no accounts. Full history.
- **Optional purchase, reporting:** pediatrician PDF ("since last visit"),
  trends, weekly summary, CSV export, multiple babies, caregiver notes.
- **Never:** ads, AI panels or predictions, moving the four buttons in an
  update, paywalling anything that already shipped free.
- **Pricing start:** $3.99/mo with a free trial, $24.99/yr, $39.99 lifetime.
  Keep the monthly trial intro (fleet rule). PPP via `~/ios/pricing`.
- **Timing:** see marketreport.md section 8. Ship a capture-only TestFlight
  build first, so it is used from day one; real use drives the reporting features.

## Stack and identifiers

- Swift 6, SwiftUI, SwiftData, WidgetKit, WatchConnectivity (chassis). Planned:
  CloudKit sharing, ActivityKit, App Intents. **No HealthKit**: it has no infant
  data types.
- iOS 17+, watchOS 10+
- App `com.jackwallner.baby`, widget `.widget`, Watch `.watch`, Watch widget
  `.watch.widget`, tests `.tests`, UI tests `.uitests`
- App Group: `group.com.jackwallner.baby`
- App Store Connect app: **none yet**. `AppStoreReviewLinks.appStoreID` is empty.
- RevenueCat project `proj0b545ae2` (dashboard name "Create a project called
  Baby"). App Store app `app53361f54f1` ("Baby Placeholder", bundle id set, ASC
  API key and subscription key configured). Test Store app `appf48b1dd074`.
- RevenueCat entitlement lookup key `baby`, display name `Baby+`. Offering
  `default` with `$rc_monthly`, `$rc_annual`, `$rc_lifetime`, **holding only Test
  Store products**, so a real device paywall is empty until the App Store
  products exist and `scripts/rc-setup.py` attaches them.
- Public SDK key `appl_qiLuKnhdneTEYzRYOtaovXNgZRa` is in `StoreService.swift`.
  The `sk_` secret key, the public key, and `ASC_REVIEW_PHONE` are in
  `~/.baby_credentials` (never in this public repo).
- Product ids inherited from the rename: `com.jackwallner.baby.monthly`,
  `.yearly`, `.pro.lifetime`. `Baby.storekit` still carries Caffeine's prices.

## Chassis map

Keep and adapt (fleet plumbing that took several review cycles to get right):

- `Shared/Services/StoreService.swift`: RevenueCat, simulator early-return,
  intro eligibility, cached Pro in the App Group.
- `Shared/Services/ConversionDiagnostics.swift`, `Shared/Utilities/ConversionCopy.swift`,
  `BabyTests/PaywallFunnelTests.swift`, `BabyUITests/PaywallFunnelUITests.swift`:
  the paywall funnel record and its Test Store purchase probe.
- `Shared/Services/ReviewPromptService.swift`, `Shared/Utilities/AppStoreReviewLinks.swift`:
  review funnel.
- `Baby/Views/PaywallView.swift`: 3.1.2 disclosure and footer in every state.
- `Baby/Views/OnboardingView.swift`: the shared `page(...)` builder that keeps
  the CTA pixel-identical across steps, `-OnboardingStep <n>` and `-StartTab <n>`
  DEBUG flags.
- `Baby/Views/SettingsView.swift`, `Shared/Services/NotificationService.swift`,
  `Shared/Services/DataService.swift` (SwiftData cache for widgets),
  `Shared/Services/WatchSyncService.swift` (phone to Watch settings transport),
  `Shared/Utilities/{Theme,DateHelpers,BundleVersion,ScreenshotConfig}.swift`,
  widget and Watch complication shells, `Baby/PrivacyInfo.xcprivacy`.

Replace (Caffeine's domain under Baby names):

- `Shared/Models/BabyRecords.swift`, `Shared/Services/BabyLogService.swift`,
  `Shared/Services/HealthKitService.swift`, `Shared/Services/HealthInsightsService.swift`,
  `Shared/Services/GoalSettings.swift` (bedtime and half-life settings),
  `Shared/Utilities/{BabyClearance,BabyInsights,BabyFormat,DrinkPresets,ScreenshotFixtures}.swift`,
  `Baby/Views/BabyViews.swift` (Now, Cutoff, Timeline tabs),
  `Baby/Views/BodyInsightsView.swift`, `BabyWatch/Views/WatchBabyView.swift`,
  `BabyTests/{BabyClearanceTests,BabyInsightsTests}.swift`.
- HealthKit entitlements in every `.entitlements`, `NSHealth*UsageDescription`
  in both Info.plists, `HEALTHKIT` in `scripts/asc-register-identifiers.py`.
- Every user-facing string: the rename made them nonsense ("How much baby").
- App icons in `Baby/Assets.xcassets`, `BabyWatch/Assets.xcassets` and
  `docs/icon_256.png`, plus `OnboardingMark`: all still Caffeine's artwork.

## App Review constraints

- **4.3:** Protein and Caffeine were both rejected as design spam. A reviewer
  on a fresh install must reach the first-week tally and a preview of the
  pediatrician summary without a purchase or days of data. Screenshots and
  review notes must show them.
- **1.4.1 and 1.1.6:** diaper and feed counts are "typical range" and "call your
  pediatrician if", cited, never normal or abnormal. Keep a disclaimer in
  onboarding, the tally screen, and Settings.
- **3.1.2:** every paywall state, and any onboarding step that can purchase,
  renders the billed amount, the disclosure, Restore, Terms of Use and Privacy
  Policy. The EULA link goes in every localized description.
- Not a Kids Category app: the user is the parent.
- No prices, `free`, or discounts in screenshots or screenshot headers, and no
  price figures in descriptions.
- `scripts/asc-configure-listing.py` refuses to run until `REVIEW_NOTES` is
  written for this app (the Daylight notes were removed).

## Fleet registration

Done 2026-09-11: GitHub repo `jackwallner/baby`, portfolio mirror
(`sync_ios_pages.py` APPS, `docs/projects.json`, `PORTFOLIO_DEPLOY_KEY`),
`~/ios/fleet-audit-823/fleet_manifest.json` (`audit_status: pending`),
`~/ios/fleet-probe/probe_config.json` `ignore_apps.baby`, the `ios-dev` skill
fleet map, `~/.baby_credentials`, memory `project_baby`.

Deferred until the App Store Connect record exists, each for a concrete reason:

- `~/.rc-clean/apps.json` here and on the MacBook Pro (`192.168.4.25`): the
  cleaner calls ASC with the app id, and a null id crashes the local serial
  run. Add `"com.jackwallner.baby": {"rc": "0b545ae2", "asc": "<id>", "name": "Baby Tracker"}`.
- Set `asc_app_id` in the fleet manifest, delete `ignore_apps.baby`, then run
  `~/ios/fleet-probe/deploy.sh` and `~/ios/crashwatch/deploy.sh` (crashwatch
  skips apps without an ASC id).
- `AppStoreReviewLinks.appStoreID`, the `apple-itunes-app` meta tag in
  `docs/index.html`, and an Astro app for keyword tracking (move the terms from
  research app `131`).

## Release

Run `xcodegen generate`, tests on a leased simulator UDID, then
`./scripts/testflight.sh`. Before the first TestFlight: register identifiers
(`scripts/asc-register-identifiers.py`, after removing `HEALTHKIT` and adding
what CloudKit needs), create the ASC record, create the products
(`asc-setup-subscriptions.py`, `asc-setup-lifetime-iap.py`), then
`RC_KEY=$RC_SECRET_KEY python3 scripts/rc-setup.py` with
`~/.baby_credentials` sourced.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing, review funnel, gotchas):
always-loaded global CLAUDE.md + the `ios-dev` skill.
