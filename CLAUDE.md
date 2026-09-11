# Baby Tracker: Feeds & Diapers

A baby tracker for the first months: one tap to log a feed, a wet or dirty
diaper, or sleep, and one glance to answer "when did she last eat, and which
side". Planned XcodeGen project and scheme: `Baby`. Simulator lease owners:
`baby` and `baby-watch`.

## Status (2026-09-11)

**No app code yet.** The build is deliberately left for a separate session.
Everything operational is done: identifiers, the App Store Connect record,
products and prices, RevenueCat, TestFlight group, site, and fleet registration.

- There is no `project.yml`, no Swift, and no `.storekit` in this repo. Create
  them from the reference copy below.
- `research/donor-code/caffeine-app/` is `~/caffeine` at `7baa2f9`, untouched:
  the iOS app, widget, Watch app, Watch widget, tests, `project.yml`, and
  `Caffeine.storekit`, under their original names. It is reference, not a build
  target. Delete it once the app has its own code, because it holds Caffeine's
  RevenueCat key.
- `scripts/` is the Caffeine release tooling renamed to Baby, with the later
  fixes from `~/daylight` at `48d0560` (`asc_lib.py` retry and backoff, review
  phone read from `~/.baby_credentials`, `--replace` review screenshots).
- `docs/` is a pre-release landing page, privacy policy, terms, and support page
  written for this app. Re-verify the privacy policy against what ships.

## Read first

Items marked (local) are gitignored because this repo is public: they carry
personal dates and fleet revenue figures. They exist on this Mac only.

1. `marketreport.md` (local): verdict, demand, competition, the #1 app's revolt,
   product angle (free capture, optional reporting, never list, stain helper),
   pricing, positioning, channels, risks. **This is the brief.**
2. `research/idea-screen-2026-09-11.md` (local): the fleet idea screen that led here.
3. `research/data/`: the baby screen scripts and raw output
   (`baby-screen-2026-09-11-raw.txt`, local).
4. `aso-plan.md`: keyword table, subtitle candidates, screenshot story.
5. `research/donor-docs/`: `caffeine-CLAUDE.md` (the donor's guide: 4.3 story,
   onboarding CTA frame, paywall rules), `babydocs-CLAUDE.md` +
   `babydocs-design.md` + `babydocs-design-audit.py` (sibling newborn app, why
   CloudKit `CKShare` rather than a server, an enforced design system), and the
   fleet playbooks `current-paywall-playbook.md`, `trial-conversion-thumb-zone.md`,
   `simulator-testing.md` (canonical copies in `~/ios/`).
6. `research/donor-code/`: `caffeine-app/` (above), `simpleglp-widget-intent/`
   (one-tap log button in a widget via `AppIntent`), `posture-live-activity/`
   (ActivityKit Live Activity and its controller).

## Reusable parts of the Caffeine reference

Worth porting (fleet plumbing that took several review cycles to get right):
`Shared/Services/StoreService.swift` (RevenueCat, simulator early-return, intro
eligibility, cached Pro in the App Group), `ConversionDiagnostics.swift` +
`ConversionCopy.swift` + `PaywallFunnelTests` + `PaywallFunnelUITests` (paywall
funnel record and Test Store purchase probe), `ReviewPromptService.swift` +
`AppStoreReviewLinks.swift`, `PaywallView.swift` (3.1.2 footer in every state),
`OnboardingView.swift` (shared `page(...)` builder keeping the CTA frame fixed),
`DataService.swift`, `WatchSyncService.swift`, `Theme.swift`, the widget and
complication shells.

Not relevant: the caffeine domain (half-life math, drink presets, HealthKit and
body insights, Now/Cutoff/Timeline tabs) and Caffeine's artwork.

## Stack and identifiers

- Planned: Swift 6, SwiftUI, WidgetKit, ActivityKit, App Intents, WatchConnectivity,
  CloudKit sharing. **No HealthKit**: it has no infant data types.
- iOS 17+, watchOS 10+, team `YXG4MP6W39`.
- Bundle IDs registered in ASC: app `com.jackwallner.baby` (App Groups, In-App
  Purchase, iCloud, Push Notifications), `.widget` (App Groups), `.watch` (App
  Groups, iCloud), `.watch.widget` (App Groups). App Group
  `group.com.jackwallner.baby` and the iCloud container are created by Xcode
  automatic signing on the first build.
- App Store Connect app **`6811133796`**, name `Baby Tracker: Feeds & Diapers`,
  SKU `com.jackwallner.baby`, version 1.0 `PREPARE_FOR_SUBMISSION`.
- RevenueCat project `proj0b545ae2` (dashboard name "Create a project called
  Baby"), App Store app `app53361f54f1`, Test Store app `appf48b1dd074`.
  Entitlement lookup key **`baby`**, display name `Baby+`. Public SDK key
  `appl_qiLuKnhdneTEYzRYOtaovXNgZRa`. The `sk_` key, the public key, and
  `ASC_REVIEW_PHONE` are in `~/.baby_credentials`, never in this repo.

## Store setup already done

- Listing: name, privacy URL, support and marketing URLs (github.io/baby),
  primary category Medical, secondary Health & Fitness (matching Baby Tracker -
  Newborn Log, Huckleberry, Nestling), copyright, manual release, content rights,
  age rating (Vitals answers), review contact. Declared **not** a regulated
  medical device. Free app, available in all 175 territories.
- Products (subscription group `Baby Plus`, display `Baby+`):
  - `com.jackwallner.baby.monthly` $3.99, 1-week free trial in all territories
  - `com.jackwallner.baby.yearly` $24.99, 1-week free trial in all territories
  - `com.jackwallner.baby.pro.lifetime` $39.99 non-consumable
  - Fleet PPP ladder applied (`~/ios/pricing/plan_baby.py`, 348 subscription
    rows, 23 lifetime territories).
  - All three are `MISSING_METADATA` until a paywall review screenshot is
    uploaded from the real app (`scripts/asc-finish-products.py`).
- RevenueCat: the three App Store products are attached to entitlement `baby`
  and the `default` offering (`$rc_monthly`, `$rc_annual`, `$rc_lifetime`);
  the public offerings endpoint serves 3 packages.
- TestFlight: internal group `jack` with access to all builds.

## Still to do, and why it waits for the app

- Review screenshots for the three products, description, keywords, subtitle,
  screenshots, `REVIEW_NOTES` in `scripts/asc-configure-listing.py`: all
  describe the real app.
- App Privacy labels (ASC web UI only): depend on the SDKs that ship. Fleet
  norm with RevenueCat only is Purchases (App Functionality, Analytics), not
  linked to tracking.
- Fleet probe: `~/ios/fleet-probe/probe_config.json` `ignore_apps.baby` stays
  until app code with the RevenueCat key exists; then delete the entry and run
  `~/ios/fleet-probe/deploy.sh`.
- Astro: temporary app `132` tracks 28 keywords; migrate to `6811133796` at launch.
- Replace `docs/icon_256.png` (Caffeine's artwork, also mirrored to jackwallner.com).

## App Review constraints

- **4.3:** Protein and Caffeine were both rejected as design spam. A reviewer
  on a fresh install must reach the first-week tally and a preview of the
  pediatrician summary without a purchase or days of data.
- **1.4.1 and 1.1.6:** diaper and feed counts are "typical range" and "call your
  pediatrician if", cited, never normal or abnormal. Disclaimer in onboarding,
  the tally screen, and Settings.
- **3.1.2:** every paywall state and any purchasing onboarding step renders the
  billed amount, disclosure, Restore, Terms of Use and Privacy Policy. EULA link
  in every localized description, no price figures in descriptions.
- Medical category keeps claims scrutiny high: never diagnose or assess.
- Not a Kids Category app: the user is the parent.

## Fleet registration

GitHub `jackwallner/baby` (public, Pages on `/docs`), portfolio mirror and
`docs/projects.json`, `PORTFOLIO_DEPLOY_KEY`, `~/ios/fleet-audit-823/fleet_manifest.json`,
`~/.rc-clean/apps.json` on this Mac and the MacBook Pro, fleet-probe and
crashwatch redeployed with the ASC id, Astro app `132`, the `ios-dev` skill
fleet map, memory `project_baby`.

## Release

Once the app exists: `xcodegen generate`, tests on a leased simulator UDID, then
`./scripts/testflight.sh` (the ASC record and TestFlight group are ready).

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing, review funnel, gotchas):
always-loaded global CLAUDE.md + the `ios-dev` skill.
