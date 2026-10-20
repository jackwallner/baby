# CloudKit setup and verification

This native Mac setup tool uses `Shared/Models/BabyModel.swift` directly. It
does not include purchases, the app UI, or a copied schema definition.
Every run uses isolated temporary local stores. It never opens the app's
existing local database.

Prerequisites: the Mac is signed into iCloud, its **Mac** provisioning UDID
is registered with team `YXG4MP6W39`, and Xcode can sign the existing
`com.jackwallner.baby` identifier. An iOS/iPod registration for the same UDID
does not satisfy Mac development signing.

From the repository root:

```sh
xcodegen generate --spec scripts/cloudkit-schema/project.yml
xcodebuild -project scripts/cloudkit-schema/BabyCloudSchema.xcodeproj \
  -scheme BabyCloudSchema -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativeCloudSchema -allowProvisioningUpdates build
```

The Debug executable is
`build/NativeCloudSchema/Build/Products/Debug/BabyCloudSchema.app/Contents/MacOS/BabyCloudSchema`.

- No argument: validates the model using Apple's schema dry run.
- `--initialize-development`: creates the Development schema using Apple's
  representative records, which the framework removes after initialization.
- `--verify-sync`: creates a clearly named temporary baby and one diaper log,
  verifies export, imports both into a fresh local store, then deletes the
  fixture and verifies its cloud records are gone. This writes real test data
  to the signed-in account. Do not run it as a read-only status check.
- `--verify-share`: creates a temporary baby, puts a real `CKShare` on its zone,
  checks the invitation URL, that the share sits in its own zone, that it is
  invite-only rather than publicly readable, then stops sharing and confirms the
  zone is purged. This is the owner half of partner sharing; the accept half
  still needs a second iCloud account.
- `--list-children`: imports the account's babies into a fresh store and names
  them, so a leftover verification fixture cannot hide in the environment.
- `--verify-shared-store`: opens the app's real two-store layout (one `.private`
  and one `.shared` scope) and waits for both to report a successful CloudKit
  setup. The invited parent's baby lands in the `.shared` store, so a
  single-store check never touches that half. Allow ten minutes: a cold setup
  takes minutes per store.
- `--audit-events`: read-only. For each Core Data zone, counts babies,
  entries, widget-written records and ids held by several records, then lists
  the 25 most recently changed entries with kind, times and who changed them.
  Prints no names or notes. Run the Release build to read Production.
- `--compare-event-layout`: read-only. Finds one `CD_LogEvent` the app
  exported and checks that `CloudEventWriter` (the widget's direct write)
  writes the same fields with the same value kinds. Prints field names and
  kinds only. Run the Release build to check Production.
- `--verify-direct-write`: the full widget round trip in Development: the
  widget's record imports into a fresh store, an in-place change imports,
  the app's own export of the same tap folds away with `DuplicateEvents`, and
  a delete removes it. Needs the container's own export to run.
- `--verify-direct-import`: the same proof without waiting on any export:
  every record is written straight to CloudKit and a fresh store imports it.
- `--self-test`: the widget sync's local logic on an in-memory store, for a
  Mac with no free simulator.

Core Data schedules its own CloudKit work as discretionary. Under heavy load
(a load average in the hundreds) the system defers it indefinitely and the
`--verify-*` modes time out waiting on export or import with no error, the
setup stuck in `_saveZone`. That is the Mac, not the app: rerun when it is
quiet. The widget's direct writes are user-initiated and are not deferred.
- `--purge-share-zones`: deletes the `com.apple.coredata.cloudkit.share.*` zones
  a failed verification leaves behind. It never touches
  `com.apple.coredata.cloudkit.zone`, where the app's own records live.

**`cloudkit.share` is a record type, and it is not created by schema
initialization.** `initializeCloudKitSchema` only creates `CD_Child` and
`CD_LogEvent`, so a Production container that was deployed from that alone
rejects every real invitation with `Cannot create new type cloudkit.share in
production schema` (CKError 12/2006) while local logging looks perfectly
healthy. The type only appears in Development once something actually shares a
record. Run `--verify-share` against Development first, then deploy Development
to Production, then run it against Production. Do this again after any model
change that redeploys the schema.

Sharing also fails with a missing `ANSCKRECORDMETADATA` table if it runs before
Core Data has finished its first CloudKit setup, which takes about two minutes
on a new store. Wait for a record to export before sharing;
`SharingService.waitForFirstExport(of:)` does this in the app.

**Launch it through LaunchServices, never by running the executable path.**
Core Data schedules its CloudKit export and import through
`BGSystemTaskScheduler`, and that service is unreachable in a process started
straight from a shell: setup succeeds, then every activity submission fails
with `BGSystemTaskSchedulerErrorDomain Code=3` and nothing ever exports, which
surfaces as `syncTimedOut`. Use `open` and read the redirected output:

```sh
open -W --stdout /tmp/baby-sync.log --stderr /tmp/baby-sync-err.log \
  build/NativeCloudSchema/Build/Products/Release/BabyCloudSchema.app \
  --args --verify-sync
```

After initialization, inspect Development in CloudKit Console and deploy its
additive changes to Production. Do not reset the environment. The initial
schema contains `CD_Child` (15 fields), `CD_LogEvent` (24 fields), and the
built-in `Users` type. Core Data did not generate a `CDMR` type for this model.

For a Production sync check, build with `-configuration Release` and use
the executable under `Build/Products/Release/`. That configuration is signed
with `SchemaProduction.entitlements`. Confirm its signed CloudKit environment
before running `--verify-sync`. The Release tool refuses schema initialization.

A successful same-account round trip is not a two-parent sharing test. The
final acceptance test still needs two different iCloud accounts: invite the
second parent, open the link with the app closed, log on both sides, verify
the same history, and confirm leaving the share preserves the owner's log.
