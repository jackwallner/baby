# Two-parent acceptance test

Accepting an invitation needs two different iCloud accounts, because CloudKit
will not let one account join its own log. Everything else about logging
together is verified automatically.

## Verified without a second account

`scripts/cloudkit-schema --verify-share`, Production, 2026-09-13, using the
app's own `Shared/Services/ShareInvite.swift`:

- A baby is shared into its own zone and the invite link is saved to iCloud as
  read/write (server record, Core Data's cache, and the share metadata a
  second phone resolves from the link all agree).
- A whole invite message pasted into Join parses back to the exact link.
- The QR code decodes back to the exact link.
- Stopping sharing from Apple's sheet (share record deleted on the server) and
  inviting again produces a new working read/write link on the same log.
- Stopping purges cleanly.

App tests (in-memory two-store stack): every logging path on a joined baby
(tap, editor, timer start and stop, Watch relay) writes into the shared store;
the joining screen lasts until the invited baby arrives and can be abandoned
without deleting anything; entries logged before joining move into the shared
baby with every field intact; a non-invite link is rejected before iCloud is
touched. UI tests cover onboarding's Start/Join choice, the joining screen,
the invite code and link, and the Join sheet.

## Watching a real two-phone test from the Mac

The owner's iCloud is the Mac's account, so the Mac can see the owner's side
of the server while two phones run the app. Read-only:

```sh
open -W --stdout /tmp/baby-watch.log --stderr /tmp/baby-watch-err.log \
  build/NativeCloudSchema/Build/Products/Release/BabyCloudSchema.app \
  --args --watch-shares 120
```

`BABY_WATCH_SHARE ... link=read-write` means the invite is open.
`BABY_WATCH_PARTICIPANT ... status=accepted` means the other phone joined.
`BABY_WATCH_ENTRY ... created_by=someone-else` is an entry the other phone
wrote, proven to have crossed into the owner's log.

## Mac as the owner, a simulator as the joining phone

For a run without a second person: sign one simulator into a different
iCloud account, then run the Mac as owner in Development and hand its link to
`TwoDeviceParticipantUITests`:

```sh
open -n -W --stdout /tmp/baby-host.log --stderr /tmp/baby-host-err.log \
  build/NativeCloudSchema/Build/Products/Debug/BabyCloudSchema.app \
  --args --host-partner-test 30
# copy BABY_HOST_INVITE_URL from /tmp/baby-host.log, then:
TEST_RUNNER_BABY_INVITE_URL='<link>' xcodebuild test -project Baby.xcodeproj \
  -scheme BabyUITests -destination "id=<signed-in simulator>" \
  -only-testing:BabyUITests/TwoDeviceParticipantUITests
```

The simulator joins through onboarding, sees the Mac's entries, logs two of
its own (the Mac reports them as `BABY_HOST_PARTNER_ENTRY`), and waits for the
Mac's reply entry. The fixture is removed at the end.

## What to run

Both phones on the same TestFlight build, signed into different iCloud
accounts. Phone A is signed into the same Apple Account as the Mac.

1. **Owner invites.** Phone A: More, Invite someone, Create invite. A QR code
   appears.
2. **New phone joins from onboarding.** Phone B: fresh install, choose Join a
   shared log, Open scanner, scan phone A's code. Expect "Joining the shared
   log", then phone A's baby and history. No second baby is created.
3. **Camera route.** Repeat with a third account or after leaving: scan with
   the Camera app with Baby Tracker force-quit (cold start).
4. **Both sides log.** Wet diaper on B, sleep on A. Each appears on the other
   phone. The watcher shows B's entry as `created_by=someone-else`.
5. **Owner sees who joined.** Phone A: More, Log together shows phone B's name.
6. **Logged before joining.** On a phone that already logged its own baby,
   join; accept "Move entries". The entries appear on both phones.
7. **Offline.** B offline, log a feed, reconnect. It reaches A exactly once.
8. **Leaving and stopping.** B leaves: B loses the shared baby, A keeps every
   entry including B's. A stops sharing: A keeps everything; inviting again
   works.
