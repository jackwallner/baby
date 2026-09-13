# Two-parent acceptance test

The owner-side checks below are verified automatically. Invitation acceptance
still needs two people, because CloudKit will not let one account accept its
own invitation. Jack confirmed on September 12 that this test has not run yet.

Verified without a second account (`scripts/cloudkit-schema`, Production):

- The schema has `CD_Child`, `CD_LogEvent` and `cloudkit.share`.
- A record exports, imports into a fresh store, and deletes cleanly.
- A real `CKShare` is created on the baby's own zone, is invite-only, carries an
  `icloud.com` invitation URL, and stops cleanly.
- The app's two-store layout, private and shared scope both, completes CloudKit
  setup against Production. The invited parent's baby arrives in the shared
  store, so this is the half a single-store check would miss.

Not verified without a second account: accepting the invitation.

## What to run

Both phones on the latest release-candidate TestFlight build, signed into
**different** iCloud accounts, both with iCloud Drive on. Record the build
number and results before calling sharing release-ready.

1. **Owner invites.** On phone A, log one feed. More > Share with your partner.
   Read the shared-log explanation, tap Invite partner, and send the Apple
   invitation link to phone B.
2. **Cold-start accept.** Force-quit Baby Tracker on phone B first, then open
   the link. This is the path that was broken before build 7: the app has to
   handle the invitation from a launch, not just while running.
3. **Both sides log.** Add a wet diaper on B and a sleep on A. Confirm both
   appear on the other phone. Keep both phones online and record any delay
   or error. Edit an entry on B and confirm the change reaches A.
4. **The invited parent keeps their own babies.** If phone B already had a baby,
   confirm it is still there and still has its events. Joining must never
   replace or delete an existing log.
5. **History agrees.** Open History on both. Same events, same times.
6. **Offline recovery.** Take B offline, add a feed, then reconnect. Confirm
   the entry reaches A exactly once and the two histories agree.
7. **Leaving is safe.** On phone B, leave the share. Phone B loses the shared
   baby and keeps its own. Phone A still has the complete log, including the
   events phone B added.
8. **Stopping is safe.** On phone A, stop sharing. Phone A keeps every event.

## If step 2 fails

Check that phone B is on build 7 or later. The cold-start path arrives through
`SceneDelegate.scene(_:willConnectTo:options:)`, which earlier builds did not
implement, so the invitation was silently dropped.
