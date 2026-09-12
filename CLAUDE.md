# Baby Tracker: Feeds & Diapers

One tap to log a feed, a wet or dirty diaper, or sleep, and one glance to
answer "when did she last eat, and which side". XcodeGen project and scheme:
`Baby`. Simulator lease owners: `baby` and `baby-watch`.

## Product

The everyday app is one screen: last feed and side, last diaper, Feed / Wet /
Dirty / Sleep controls, and quiet daily totals. History is one tap away through
the top-left clock. More is the top-right ellipsis.

Everything outside logging lives in More: First Weeks, Pediatrician summary,
partner sharing, stain helper, baby settings, and Baby+. No tab bar, automatic
review prompts, promotional cards, or purchase screen during onboarding.
Onboarding is one optional name/birth-date screen with Start tracking.

Never: ads, AI panels or predictions, moving or renaming the four buttons, or
locking something that shipped free.

## Architecture

- Swift 6, SwiftUI, Core Data + `NSPersistentCloudKitContainer`, WidgetKit,
  ActivityKit, App Intents, WatchConnectivity. **No HealthKit**: it has no
  infant data types.
- iOS 17+, watchOS 10+, team `YXG4MP6W39`.
- `Persistence` opens two stores against one model: `private.sqlite` mirrored to
  the private CloudKit database, and `shared.sqlite` mirrored to the shared one.
  A baby another parent shared arrives in the second store, and every query runs
  across both. Only the app process mirrors; widgets and intents open the same
  files with mirroring off and write, and the app exports their rows from
  persistent history on its next run.
- `EventStore` is the single door to the log: every tap, edit, undo and delete
  goes through it, and it republishes `NowSummary` to the widgets, the Watch and
  the Live Activity after each change.
- `NowSummary` is the one derived value (last feed and side, last diaper,
  running feed or sleep, today's counts). The Watch keeps its own copy plus the
  taps the phone has not confirmed, so the wrist never shows a stale answer.
- `SummaryReport` derives the daily rows, the CSV and the PDF numbers; it is
  pure, so the page, the charts and the export cannot disagree.
- Sharing is `CKShare` on the baby's record zone through `UICloudSharingController`.
  No accounts, no server.

Key files: `Shared/Services/Persistence.swift`, `EventStore.swift`,
`NowSummary.swift`, `SummaryReport.swift`, `SharingService.swift`,
`WatchSyncService.swift`, `WatchStore.swift`, `StoreService.swift`,
`Shared/Utilities/Guidance.swift`, `StainGuide.swift`, `AppTheme.swift`,
`AppIntents.swift`, `Baby/Views/`, `BabyWidget/`, `BabyWatch/`.

## Design system

`Shared/Utilities/AppTheme.swift` holds every spacing, radius and colour, and
`python3 scripts/design-audit.py` fails any view that types its own. Four-point
spacing scale, one 20pt margin, one continuous 20pt radius, colour that means
only "which of the four kinds this is". Run the audit before a release.
Motion respects Reduce Motion; accessibility text sizes use stacked layouts.

## Access model

Free forever: logging, the first-weeks tally, full history, both widgets, the
Watch app and complication, the Live Activity, partner sharing, the stain
helper.

Baby+ (`PlusFeature`): sharing or exporting the pediatrician PDF, the trends
charts, CSV export, and more than one baby. Nothing else may move behind it.

## Identifiers

- App `com.jackwallner.baby`, widget `.widget`, Watch `.watch`, Watch widget
  `.watch.widget`, tests `.tests`, UI tests `.uitests`.
- App Group `group.com.jackwallner.baby`, iCloud container
  `iCloud.com.jackwallner.baby`.
- App Store Connect app **`6811133796`**, version 1.0.
- RevenueCat project `proj0b545ae2`, entitlement lookup key **`baby`**, display
  name `Baby+`, public SDK key `appl_qiLuKnhdneTEYzRYOtaovXNgZRa`. The `sk_`
  key, the Test Store key and `ASC_REVIEW_PHONE` live in `~/.baby_credentials`,
  never in this repo.
- Products: `com.jackwallner.baby.monthly` $3.99 (1-week trial),
  `.yearly` $24.99 (1-week trial), `.pro.lifetime` $39.99. All three are
  `READY_TO_SUBMIT`.

## Screenshots and renders

- `BabyUITests/PaywallScreenshotUITests` renders the real paywall under StoreKit
  Testing, one plan at a time (`-PaywallSnapshot yearly|monthly|lifetime`), and
  attaches the PNG. `scripts/asc-upload-review-screenshots.py --dir
  build/paywall-shots` puts each render on its own product, because each product
  has to show its own billed amount.
- `StoreService.start()` must keep loading simulator products when
  `ScreenshotConfig.isEnabled`. Without that the render is the "Couldn't load
  plans" state, which is exactly what App Review rejects.
- App Store screenshots use the fleet renderer with `app-store/screenshots.json`.
  Raw evidence lives in `app-store/capture/`.
- `-SeedScreenshotData` seeds a day-three newborn log; `-ScreenshotTab N`,
  and `-StartTab N` open a surface directly (all DEBUG, legacy screen numbers).

## App Review constraints

- **4.3:** a reviewer on a fresh install reaches More > First Weeks
  and More > Pediatrician summary with no purchase and no
  data. The summary preview renders a worked example stamped
  "EXAMPLE, NOT YOUR BABY'S DATA" until something is logged.
- **1.4.1 and 1.1.6:** diaper and feed counts are "typical range" and "call your
  pediatrician if", sourced to the American Academy of Pediatrics, never normal,
  abnormal or a verdict. The disclaimer is in onboarding, First Weeks, Summary
  and Settings. Declared not a regulated medical device.
- **3.1.2:** every paywall state, including loading and failure,
  renders the billed amount, the renewal disclosure, Restore,
  Terms of Use and Privacy Policy. No price figures in the description.
- Not a Kids Category app: the user is the parent.

## Release

`xcodegen generate`, tests on a leased simulator UDID, then
`./scripts/testflight.sh`. ASC scripts target `6811133796`.

**CloudKit schema: deployed and verified in Production (2026-09-12).** Do not
re-run initialization or reset an environment. `scripts/cloudkit-schema/` is a
native Mac tool built from the real `Shared/Models/BabyModel.swift`; it creates
the Development schema, and its Release build verifies a Production export /
fresh-store import round trip. Read its README before touching either
environment, especially the rule that it must be launched with `open`, not by
running the executable path. Any model change needs Development initialization
and a fresh Development-to-Production deploy before the build that ships it.

## Focused rules

- `.claude/rules/interface.md`: simplicity decisions and verification expectations.
- `.claude/rules/release-verification.md`: build 5 test and screenshot evidence.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
