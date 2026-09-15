# Baby Tracker: Feeds & Diapers

One tap to log a feed, a wet or dirty diaper, or sleep, and one glance to
answer "when did she last eat, and which side". XcodeGen project and scheme:
`Baby`. Simulator lease owners: `baby` and `baby-watch`.

## Product

The everyday app is one screen: last feed and side, last diaper, Feed / Pee /
Poop / Sleep controls, and quiet daily totals. The diaper pair can read Wet /
Dirty instead (More > Diaper buttons, `DiaperWords`); reports for a doctor
always say wet and dirty. History is one tap away through
the top-left clock. More is the top-right ellipsis.

Everything outside logging lives in More: First Weeks, Pediatrician summary,
logging together, appearance, diaper words, stain helper, baby settings, and Baby+. No tab bar, automatic
review prompts, promotional cards, or purchase screen during onboarding.
Onboarding is one screen with two paths: Start a new log (optional name and
birth date) or Join a shared log (scan or paste an invite). An invitation
opened before setup shows a joining screen instead of onboarding.

Never: ads, AI panels or predictions, moving the four buttons or renaming them beyond that setting, or
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
- Logging together is one `CKShare` on the baby's record zone, opened as a
  read/write invite link (`publicPermission = .readWrite`). The owner shows a
  QR code or sends the link; the other phone scans it in the app (VisionKit),
  with Camera, taps the link, or pastes it. Every participant writes events
  into the same zone. `Shared/Services/ShareInvite.swift` holds the invite
  routine and is compiled into `scripts/cloudkit-schema` too, whose
  `--verify-share` proves it on Production and `--watch-shares` observes a
  real two-phone test (see `docs/two-parent-acceptance.md`). Apple's
  `UICloudSharingController` is only for removing people and stopping or
  leaving. No accounts, no server.

Key files: `Shared/Services/Persistence.swift`, `EventStore.swift`,
`NowSummary.swift`, `SummaryReport.swift`, `SharingService.swift`,
`WatchSyncService.swift`, `WatchStore.swift`, `StoreService.swift`,
`Shared/Utilities/Guidance.swift`, `StainGuide.swift`, `AppTheme.swift`,
`AppIntents.swift`, `Baby/Views/`, `BabyWidget/`, `BabyWatch/`.

## Design system

`Shared/Utilities/AppTheme.swift` holds every spacing, radius and colour, and
`python3 scripts/design-audit.py` fails any view that types its own. Four-point
spacing scale, one 20pt margin, one continuous 20pt radius, outlined care
graphics and firm card edges. Kind colors distinguish the four logging actions;
peach marks primary actions. Appearance is System, Light, Dark or Night light.
Only light has the offset ink shadow; dark themes use a hairline `edge` and
tonal surfaces. Night light is a trait (`NightLightTrait`) bridged into SwiftUI,
so every `Color(light:dark:night:)` re-resolves live. Run the audit before a release.
Motion respects Reduce Motion; accessibility text sizes use stacked layouts.

## Access model

Free forever: logging, the first-weeks tally, full history, both widgets, the
Watch app and complication, the Live Activity, logging together, the stain
helper, every appearance, more than one baby.

Baby+ (`PlusFeature`) is reporting to share with a doctor: sharing or exporting
the pediatrician PDF, the trends charts, and CSV export. Nothing else may move
behind it. More than one baby is free.

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
- **1.4.1 and 1.1.6:** First Weeks labels its diaper/feed table as a breastfeeding
  reference for the first two weeks, sourced to NHS Healthier Together. It never
  assesses logged counts against a target. AAP sources support newborn feeding
  and age-qualified fever advice. The disclaimer is in onboarding, First Weeks, Summary
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
environment, especially two rules: it must be launched with `open`, not by
running the executable path, and `cloudkit.share` is a record type that schema
initialization never creates, so Production rejects every invitation until
something shares a record in Development and that is deployed. Any model change needs Development initialization
and a fresh Development-to-Production deploy before the build that ships it.

## Focused rules

- `.claude/rules/interface.md`: simplicity decisions and verification expectations.
- `.claude/rules/graphic-style.md`: graphic vocabulary, responsive layouts, and guidance scope.
- `.claude/rules/release-verification.md`: build 5 test and screenshot evidence.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
