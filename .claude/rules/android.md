---
paths:
  - "android/**"
  - "scripts/android-golden/**"
  - "firebase/**"
---

# Baby Tracker Android

Native Kotlin/Compose port in `android/`, screen for screen with iOS where the
platform allows. First built 2026-10-20 on jmbp2 (fleet run
`shift-android-baby-1-1792553156`). Not uploaded to Play yet.

## Identity

- Package and namespace `com.jackwallner.baby` (permanent once uploaded).
  Listing name `Baby Tracker: Feeds & Diapers`. minSdk 26, target/compile 36.
  versionCode 1, versionName 1.0.0.
- Same RevenueCat project `proj0b545ae2`, entitlement `baby`, offering
  `default` with `$rc_monthly`, `$rc_annual`, `$rc_lifetime`. The app treats
  any active entitlement as Baby+, as iOS does.
- Play products to create (same ids as iOS, prices from iOS: monthly $3.99,
  yearly $24.99, lifetime $39.99): subscription `com.jackwallner.baby.monthly`
  with base plan `monthly` and a 1-week free-trial offer; subscription
  `com.jackwallner.baby.yearly` with base plan `yearly` and a 1-week free-trial
  offer; in-app product `com.jackwallner.baby.pro.lifetime`. RevenueCat names
  them `<id>:<basePlan>`.
- Debug builds use the Test Store app `appf48b1dd074` key (`REVENUECAT_TEST_KEY`
  in ignored `android/local.properties`, read from the RC API with the secret in
  `~/.baby_credentials`). Release needs `REVENUECAT_PLAY_KEY` (`goog_`), which
  does not exist until a Play app is added to `proj0b545ae2`.

## Parity with iOS (how it is checked)

- `scripts/android-golden/export.sh` compiles the real iOS sources
  (`BabyModel`, `NowSummary`, `SummaryReport`, `Reminders`, `DateHelpers`,
  `Guidance`, `StainGuide`, `TrackedKinds`, `DiaperWords`) with a small
  exporter and writes `android/app/src/test/resources/golden.json`.
  `GoldenParityTest` asserts the Kotlin port gives the same lines, counts,
  totals, hour strip, report days, averages note, weight change, CSV, format
  strings, guidance table, stain steps, reminder plans and headlines. Rerun the
  exporter after changing any of those Swift files, then the JVM tests. Needs
  only `swiftc` (Command Line Tools), not Xcode.
- Events are handed to `NowSummary`, `DayTally` and `SummaryReport` newest
  first on both platforms; order matters for stool colours and a day's weight.

## Deliberate differences from iOS

- **Not ported yet (2026-10-21):** iOS's All button, Settings > Feed types
  and the side chips inside the Feed button. Port them with parity tests.
- **Log together uses Firebase, not CloudKit** (Jack, 2026-10-20). Firebase
  Auth with Google sign-in (Credential Manager) and Cloud Firestore, Spark
  plan only: never enable billing or Blaze. One Firestore family per shared
  log holds every baby on the phones in it (iOS shares per baby); joining
  adds the joiner's own babies too. Android to Android only in v1: an iPhone
  partner cannot join yet, and every sharing screen says so. Schema, rules,
  Console steps and the iOS path are in `firebase/README.md`.
  - `SharingService` (Firebase), `CredentialSignIn`, pure rules in
    `model/Sync.kt` (`SyncDiff` stamps and diffs, `SyncMerge` newest
    `updatedAt` wins with tombstones, `SyncDocs` field maps, `InviteCode`).
    `EventStore.isShared` stamps every change; `onCommit` hands it to the
    service; `applyRemote` merges without echoing. Undo's snapshot is rebased
    on arriving rows, except the rows the action touched.
  - Local only is the default. No `android/app/google-services.json` (git
    ignored, read by Gradle without the Google Services plugin) means
    sharing is hidden; `validateReleaseConfiguration` fails release builds
    without it or without a web OAuth client in it.
  - Leaving deletes the member doc and the Firebase Auth user (Play account
    deletion); the last member out deletes the family. Removal by the owner
    withdraws this phone's open invite.
  - Onboarding has iOS's two paths (Start a new log, Join a shared log) only
    when sharing is available. Invite links:
    `https://jackwallner.github.io/baby/join.html#CODE` (page in `docs/`) and
    `babytracker://join/CODE`.
- No widgets, Watch, Live Activity, controls or Siri in v1 (Glance and Wear OS
  are separate projects).
- Storage is one JSON file (`files/baby-log.json`, written atomically), not
  Core Data. Android backup may copy it to the user's Google account; the
  privacy policy says so. With Log together on, Firestore's offline cache is
  a second copy and the JSON file stays the app's source for the screen.
- CSV `date` column is the local calendar day. iOS formats it with
  `.iso8601.year().month().day()`, which is UTC, so an evening entry in the
  Americas lands on the next day there. That is an iOS bug worth fixing
  (`SummaryReport.csv`); the parity test compares every other column.
- Reminders are inexact `AlarmManager` alarms (no exact-alarm permission or
  Play declaration) and are re-armed after reboot by `BootReceiver`.
- Settings "Rate Baby Tracker" opens the Play listing; "Send Feedback" is a
  mail draft. No in-app review prompt (iOS has none either).
- Terms link to `https://jackwallner.github.io/baby/terms.html` (iOS uses
  Apple's standard EULA, which does not apply on Play).
- Reduce Motion is the system "Remove animations" setting (animator scale 0).

## Build and test (fleet machines, never on the Air)

Run Gradle from `android/` through `fm-gradle` (see `android-dev`), not `./gradlew`:

```sh
cd android
fm-gradle :app:testDebugUnitTest -Pkotlin.compiler.execution.strategy=in-process
fm-gradle :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug -Pkotlin.compiler.execution.strategy=in-process
ANDROID_SERIAL=emulator-5554 fm-gradle :app:connectedDebugAndroidTest -Pkotlin.compiler.execution.strategy=in-process
```

- jmbp2 has 8 GB: stop Gradle (`./gradlew --stop`) before booting
  `agent-emu-1` (API 36 Play image, x86_64, SwiftShader). Boot headless with
  `-no-window -no-audio -no-boot-anim -no-metrics -no-snapshot-save`.
  Stop it with `adb -s emulator-5554 emu kill`.
- Connected tests use the orchestrator with `clearPackageData`, so each test
  starts at onboarding.
- Log together tests need the Firebase Local Emulator Suite (JDK 21 at
  `~/jdks/temurin-21` on PATH for firebase-tools, JDK 17 for Gradle). Rules:
  `cd firebase && npm ci && npx firebase-tools emulators:exec --project
  demo-baby --only firestore 'npm test'`. Connected: wrap the Gradle command
  in `npx firebase-tools emulators:exec --project demo-baby --only
  auth,firestore "..."` and add
  `-Pandroid.testInstrumentationRunnerArguments.firebaseEmulator=10.0.2.2`;
  without it `SharingSyncTests` and the emulator `SharingUiTests` report as
  skipped. Two phones run in one process (`SharingEmulator.Phone`).
- Debug launch extras (`DebugLaunchOptions`, debug source set only):
  `--ez seed true` (day-three newborn log), `--ez empty true` (reviewer
  no-data path), `--ei tab 0..3` (Log, History, Upgrade/Reports, Settings),
  `--es appearance light|dark|night|system`, `--ez plus true|false` (local
  Baby+ override), `--ez screenshot true` (no reminder offer, no paywall
  impressions), `--es firebaseEmulator 10.0.2.2 --es shareName Jack` (Log
  together on the emulators with a fake Google sign-in).
  `firebase/scripts/join-as.mjs CODE Maya` joins as a second caregiver.
- jmbp (Intel, x86_64 AVD, SwiftShader) records at about 9.5 fps in motion
  windows: native 60 fps cannot be proven there. Motion review belongs on the
  Air.

## Release preparation and remaining Play steps

1. Create the Play app `com.jackwallner.baby` in the E3 Apps account (Console,
   needs Jack's Chrome). Listing text, feature graphic and screenshots are in `android/play-assets/` (see its README),
   icon `android/play-assets/icon-512.png`. Done: the 1024 x 500 feature
   graphic and five 1080 x 2160 phone screenshots captured from real
   debug-build screens.
2. Create the three products above, review Play's generated local prices
   against the iOS PPP plan, then activate.
3. Add a Play app to RevenueCat `proj0b545ae2` (needs the Play service account,
   ask Jack), attach the products to entitlement `baby` and the `default`
   offering packages, put the `goog_` key in the Air's `local.properties`,
   and register the app with rc-clean (`~/.rc-clean/apps.json`, android block
   with `filter_platform: android`).
4. Firebase (Jack, Chrome): follow `firebase/README.md` Console setup: a
   Spark project, Android app with the upload and Play signing SHA-1s,
   Google sign-in on, Firestore in production mode, deploy
   `firebase/firestore.rules`, then put `google-services.json` at
   `android/app/` on the Air before the release build. Optional:
   `assetlinks.json` in the `jackwallner.github.io` repo so invite links open
   the app directly.
5. Policy forms from actual behaviour: `android/play-assets/data-safety.md`
   (Log together collects name, email, user id and the baby log, optional,
   encrypted in transit, deletable in app and at
   `https://jackwallner.github.io/baby/delete-account.html`; purchases go
   to RevenueCat), Health apps declaration (baby care log, not a medical
   device), ads: none, target audience: adults (parents), content rating
   questionnaire, app access: no login needed (Google sign-in optional).
6. Signed AAB and internal track upload are the Air release worker's job
   (upload key stays on the Air). Then licence-tester purchase and restore,
   pre-launch report, and production only when Jack asks.

Last verified Play state: no Play app exists (2026-10-20). No Firebase
project exists yet (2026-10-21); everything was verified on the emulators.
