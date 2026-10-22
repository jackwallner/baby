# Log together backend (Firebase)

Android "Log together" (decided by Jack 2026-10-20): Firebase Auth with
Google sign-in through Credential Manager, and Cloud Firestore. **Spark
(free) plan only: never enable billing or upgrade to Blaze.** Local only is
the default; nothing reaches Firebase until someone taps Continue with
Google or Join with Google.

Android to Android in v1. iPhones keep using CloudKit sharing, and an iPhone
partner cannot join an Android log yet (the app says so on every sharing
screen). The schema below is plain enough for the iOS app to join later.

New family ids use `<ownerUid>:<UUID>`. Existing family ids remain usable, but
cannot be recreated after deletion by an older client. This blocks claiming
orphaned legacy logs by manufacturing a replacement family document.

## Schema (version 1)

| Path | Fields |
|---|---|
| `families/{familyId}` | `ownerUid`, `createdAt` (server time), `schema` (1), optional `invitesValidAfter` (server time). Only the invitation boundary changes. |
| `families/{f}/members/{uid}` | `uid`, `name` (first name from Google), `role` (`owner` or `member`), `joinedAt` (server time), `invite` (code used, null for the owner), `platform` (`android`). |
| `families/{f}/children/{childId}` | `id`, `name`, `birthDate`, `createdAt`, `lastVisitAt`, `updatedAt`, `deleted`, `updatedBy`, `syncedAt` |
| `families/{f}/entries/{entryId}` | `id`, `childId`, `kind`, `startedAt`, `endedAt`, `side`, `amount`, `stoolColor`, `note`, `createdAt`, `updatedAt`, `deleted`, `updatedBy`, `syncedAt` |
| `invites/{code}` | `familyId`, `createdBy`, `createdAt` (server time), `expiresAt` (7 days), optional `revokedAt` (server time) |

- Babies and entries keep the Android JSON model's field names and ids
  (`android/.../model/LogState.kt`). Times are epoch milliseconds as
  integers; `amount` is millilitres (bottle) or grams (weight); `kind`,
  `side` and `stoolColor` use the raw values iOS stores (`feed`, `wet`,
  `dirty`, `sleep`, `weight`; `left,right` in tap order; `yellow`...).
- A delete is a tombstone: `deleted: true` with a newer `updatedAt`.
- **Last writer wins per row**: the rules refuse a write whose `updatedAt` is
  older than the stored one, so an offline phone can't undo a newer change
  when it reconnects; its cache then reverts to the server's row.
- `syncedAt` is the server's write time (`request.time`, enforced). Phones
  listen to `entries where syncedAt >= last seen - 5 min`, so a year-old log
  isn't re-read on every launch (Spark's 50k reads a day).
- Invite codes are 8 characters from `23456789ABCDEFGHJKLMNPQRSTUVWXYZ`
  (no 0/O, 1/I), shown as `ABCD-2345`, sent as
  `https://jackwallner.github.io/baby/join.html#ABCD2345`. Codes can be
  looked up one at a time but never listed. Every leave or removal invalidates every earlier invite atomically. An invite also requires its creator to remain a member.
- Leaving deletes your member document and your Firebase Auth user (Play's
  account deletion rule). The membership deletion must share a batch with
  `families/{f}.invitesValidAfter = serverTimestamp()`. The last member scrubs
  care fields into minimal tombstones. The family identity and row versions
  remain inaccessible to former members, preventing ownership takeover and
  delete/recreate rollback. Clients cannot hard-delete families, babies or entries.
- Bootstrap owner membership is allowed only alongside a new family. Leaving
  does not let an old owner restore their membership or remove remaining members.
- A former owner invited back as a member has ordinary member permissions.
- Withdraw an invite by setting `revokedAt = serverTimestamp()`. Invite documents
  cannot be deleted or rebound to another family, including after expiry. This
  prevents a withdrawn link from being claimed by another log and receiving a
  joining phone's private history. Do not garbage-collect these code identities.
- Existing clients must upgrade for leave/remove and last-member cleanup under
  these rules. The Android client in this change implements the new protocol.

For iOS to join later: sign in with Google (or add Apple as a second Auth
provider), read the invite, create `members/{uid}` with `platform: "ios"`,
then map `Child`/`BabyEvent` to these fields (dates to epoch millis). The
rules already accept any `platform` string up to 16 characters.

## Tests

```sh
cd firebase
npm ci
# Rules against the Firestore emulator (JDK 21+ on PATH).
npm run emulator-test
# Android connected tests (two phones, UI) against Auth + Firestore emulators:
PATH=~/jdks/temurin-21/Contents/Home/bin:$PATH npx firebase-tools emulators:exec --project demo-baby --only auth,firestore \
  "cd ../android && ANDROID_SERIAL=emulator-5560 JAVA_HOME=$HOME/jdks/temurin-17/Contents/Home ./gradlew :app:connectedDebugAndroidTest \
   -Pandroid.testInstrumentationRunnerArguments.firebaseEmulator=10.0.2.2"
```

`demo-baby` is an emulator-only project id: nothing leaves the host.
On this Mac, use `PATH=/opt/homebrew/opt/openjdk/bin:$PATH npm run emulator-test`.
Client verification runs remotely with
`cd ../android && fm-gradle :app:testDebugUnitTest :app:assembleDebug`.
`scripts/join-as.mjs CODE Name [kind]` joins a running emulator log as a
second caregiver from Node, for captures and manual checks. Debug builds
point at the emulators with `--es firebaseEmulator 10.0.2.2` (fake Google
sign-in named by `--es shareName`).

## Console setup (Jack, once, in Chrome)

1. Firebase Console: create project `baby-tracker` (Spark plan; decline
   Google Analytics). Do not add billing.
2. Add an Android app `com.jackwallner.baby`. Add SHA-1 fingerprints of the
   upload key (Air: `keytool -list -v -keystore <upload.jks>`) and, after the
   first Play upload, the Play app signing key (Play Console > Test and
   release > App integrity).
3. Authentication > Sign-in method: enable Google (support email
   jackwallner@gmail.com). Settings > User actions: leave email enumeration
   protection on.
4. Firestore: create the default database in production mode, location
   `nam5` (or the closest multi-region), then deploy rules:
   `npx firebase-tools login` then
   `npx firebase-tools deploy --only firestore:rules,firestore:indexes --project <id>` from `firebase/`.
5. Download `google-services.json` (after steps 2 and 3, so it contains the
   web OAuth client) to `android/app/google-services.json` on the Air. It is
   git-ignored. Without it the app builds with sharing hidden, and
   `validateReleaseConfiguration` fails every release build.
6. Optional: App Check with Play Integrity, once the app is on Play.
7. The invite link opens the app directly only after
   `https://jackwallner.github.io/.well-known/assetlinks.json` (the
   `jackwallner.github.io` repository, not this one) lists the Play signing
   SHA-256. Until then it opens `docs/join.html`, which shows the code and an
   "Open in Baby Tracker" button (`babytracker://join/CODE`).
