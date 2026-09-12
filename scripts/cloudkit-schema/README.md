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
- `--list-children`: imports the account's babies into a fresh store and names
  them, so a leftover verification fixture cannot hide in the environment.

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
