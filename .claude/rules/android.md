---
paths:
  - "android/**"
  - "scripts/android-golden/**"
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

- **No logging together.** CloudKit sharing has no Android equivalent and the
  app has no server. Android has one onboarding path (Start a new log) and no
  Log together section. Decision needed from Jack before any cross-platform
  sharing: a backend (for example Supabase, with accounts or invite tokens)
  or leaving Android single-device. Do not invent one.
- No widgets, Watch, Live Activity, controls or Siri in v1 (Glance and Wear OS
  are separate projects).
- Storage is one JSON file (`files/baby-log.json`, written atomically), not
  Core Data. Android backup may copy it to the user's Google account; the
  privacy policy says so.
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

## Build and test on a Pro (never on the Air)

```sh
export JAVA_HOME=~/jdks/temurin-17/Contents/Home ANDROID_HOME=~/Library/Android/sdk
cd android
./gradlew :app:testDebugUnitTest -Pkotlin.compiler.execution.strategy=in-process
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug -Pkotlin.compiler.execution.strategy=in-process
ANDROID_SERIAL=emulator-5554 ./gradlew :app:connectedDebugAndroidTest -Pkotlin.compiler.execution.strategy=in-process
```

- jmbp2 has 8 GB: stop Gradle (`./gradlew --stop`) before booting
  `agent-emu-1` (API 36 Play image, x86_64, SwiftShader). Boot headless with
  `-no-window -no-audio -no-boot-anim -no-metrics -no-snapshot-save`.
  Stop it with `adb -s emulator-5554 emu kill`.
- Connected tests use the orchestrator with `clearPackageData`, so each test
  starts at onboarding.
- Debug launch extras (`DebugLaunchOptions`, debug source set only):
  `--ez seed true` (day-three newborn log), `--ez empty true` (reviewer
  no-data path), `--ei tab 0..3` (Log, History, Upgrade/Reports, Settings),
  `--es appearance light|dark|night|system`, `--ez plus true|false` (local
  Baby+ override), `--ez screenshot true` (no reminder offer, no paywall
  impressions).

## Release preparation and remaining Play steps

1. Create the Play app `com.jackwallner.baby` in the E3 Apps account (Console,
   needs Jack's Chrome). Listing text is in `android/play-assets/listing/`,
   icon `android/play-assets/icon-512.png`. Still needed: a 1024 x 500 feature
   graphic and four 1080 x 1920 phone screenshots composited from real
   captures.
2. Create the three products above, review Play's generated local prices
   against the iOS PPP plan, then activate.
3. Add a Play app to RevenueCat `proj0b545ae2` (needs the Play service account,
   ask Jack), attach the products to entitlement `baby` and the `default`
   offering packages, put the `goog_` key in the Air's `local.properties`,
   and register the app with rc-clean (`~/.rc-clean/apps.json`, android block
   with `filter_platform: android`).
4. Policy forms from actual behaviour: Data safety (no data collected by the
   developer; purchase history and an app user id go to RevenueCat for
   purchases; no location, contacts, health records sync), Health apps
   declaration (baby care log, not a medical device), ads: none, target
   audience: adults (parents), content rating questionnaire, app access: no
   login needed.
5. Signed AAB and internal track upload are the Air release worker's job
   (upload key stays on the Air). Then licence-tester purchase and restore,
   pre-launch report, and production only when Jack asks.

Last verified Play state: no Play app exists (2026-10-20).
