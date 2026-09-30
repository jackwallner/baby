# Build 28 widget and intent audit

Audited September 29, 2026. Follow-up version: 1.1.1.

## Findings and fixes

| Finding | Result |
| --- | --- |
| Control idle state was treated as proof of a successful save. Setup and save failures returned successful intent results. | Controls read the persisted outcome through a value provider. Failed actions throw a localized error and cannot produce a new success confirmation. |
| Sleep bypassed duplicate-tap suppression and never offered widget confirmation or Undo. | Sleep and Wake offer the same confirmation and Undo as the other grid buttons. A duplicate tap keeps the original outcome. Undo of Wake reopens the same timer. |
| Widget Undo cleared its token before saving, and the app branch ignored save failures. | Failed saves preserve the token and report an error, so Undo can retry. |
| A stale widget could log for a different baby after the active baby changed. | Widget actions carry the displayed baby's id. Undo and duplicate suppression also belong to that baby. |
| A fallback baby selection left a stale id in shared preferences. | Reload repairs the selected id, keeping the app, intent and widget identity consistent. |
| An old Live Activity could stop a newer timer of the same kind. | Stop carries the activity's start time and refuses a mismatched timer. |
| Undo in the app left the widget's confirmation and duplicate suppression active. | A successful app Undo clears the matching widget state. |
| Empty space inside a plain widget button could fall through to opening the app. | The full visible log and Undo faces have explicit touch shapes. |
| Widget actions used Siri's dialog response and shared its parameter types. | A hidden widget action carries simple strings and records its save result directly. The public Siri action keeps its original parameter and dialog. |
| Wake could wrap on the Live Activity. | Its button label stays on one line. |
| App Review notes still pointed to the former More menu. | Updated to Reports and Settings. Release notes are localized in all 50 storefront locales. |
| Readiness reported already approved purchases as missing configuration. | Approved subscriptions and lifetime purchases count as ready for an update. |

## Verification

- 112 unit tests passed on the final source, including ten new regression cases for the findings above. Result: `build/audit-ui/Logs/Test/Test-Baby-2026.09.29_15-53-51--0700.xcresult`.
- Design audit: zero drift.
- Info.plist validation passed for the app, widgets, and Watch. Launch screen, camera disclosure, and encryption declaration are present.
- History deletion and Undo passed on iOS 26.5. Earlier iOS 27 runs passed the other 13 logging cases and all three paywall screenshot cases.
- The two widget runtime tests did not pass. A run saved two Pee entries and showed confirmation, but Undo opened the app. Other runs cancelled actions or never entered the logging action. The final string-parameter run failed both widget tests. Machine load exceeded 500, and UI queries also timed out outside the widgets; this does not establish that the widget failure is simulator-only.
- Widget dispatch and confirmation need a real-phone check before manual release. The unit tests prove the save, duplicate suppression, identity guards and Undo logic, but do not prove the system dispatch or touch behavior.

## App Store Connect

Version 1.1.1, build 29, was uploaded with `scripts/testflight.sh`. Archive and
export succeeded. The app, widget and Watch bundle versions are all 1.1.1 (29).
Apple validated build `762b5c4a-53ee-4585-862e-74546f2d2694`, and it is attached to
version `12c68f43-582a-4a2c-bbb4-218b450eb46b`.

Release notes are set in all 50 locales, and review instructions use the current
Reports and Settings paths. The approved purchases are retained.
`scripts/asc-readiness.py` reports no gaps and all three public URLs return 200.

Submitted at 2026-09-29 23:05:37 UTC. Review submission
`8b901895-dfff-40ce-a917-2ab70fd662d4` and the App Store version both read
`WAITING_FOR_REVIEW`. Independently read back `releaseType = MANUAL` and the
attached build 29 after submission. A phone widget check remains required before
manually releasing it.

## Physical-device limits

Apple documents `.alwaysAllowed` as the default authentication policy. Adding
the explicit property in build 28 did not itself change that policy:
[AppIntent.authenticationPolicy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy).

There is no connected physical iPhone in this session. Lock Screen circles,
corner controls, and Live Activity Wake/Stop still need a locked-device check,
after the first unlock since restarting the phone. The database uses protection
that permits access after that first unlock. User Lock Screen access settings
also apply. No two-account CloudKit delivery test was repeated.

The rectangular Lock Screen log row displays Feed, Pee and Poop. It displays
Sleep when Sleep is the only tracked kind. The Home Screen grid displays all
tracked kinds, so the earlier claim of four buttons in the Lock Screen row was
inaccurate.

## 1.1.1 replaced by 1.2 (build 31), 2026-09-30

Build 29 put `.invalidatableContent()` on and inside the widget
`Button(intent:)` views. On a re-signed simulator build the renderer treated a
tap as a plain widget tap ("Launching with no widgetURL"): the app opened, no
entry was logged and no Undo appeared. Jack's phone logged the taps but never
showed the confirmation. Either way, 1.1.1's release note ("clearer tap
confirmations") did not hold. Removing the modifier made both `WidgetUITests`
cases pass (log, Logged / Undo, Undo restores the count).

Review submission `8b901895-dfff-40ce-a917-2ab70fd662d4` was cancelled. The same
App Store version (`12c68f43-582a-4a2c-bbb4-218b450eb46b`) was renamed 1.2, given
build 31 and the staged en-US keywords (pediatrician out, feeding in), and
resubmitted as `98930747-2fba-4f52-9a78-7c04a33027ad` at 17:10 UTC. It reads back
`WAITING_FOR_REVIEW`, `releaseType = MANUAL`, build 31. `asc-readiness.py`
reported no gaps. The Lock Screen circle is still unverified on a physical
iPhone; check it before releasing.
