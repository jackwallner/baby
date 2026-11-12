---
paths:
  - "Baby/App.swift"
  - "Baby/Views/UnfoldedSplit.swift"
  - "Baby/Views/NowView.swift"
  - "Baby/Views/OnboardingView.swift"
  - "Shared/Utilities/AppTheme.swift"
  - "Baby/Info.plist"
  - "project.yml"
  - "artifacts/asc-screenshots/ipad-20261112/**"
---

# iPad layout (2026-11-12)

iPad support is free: `TARGETED_DEVICE_FAMILY "1,2"` on the app (the widget
extension already built for both), all four orientations through
`UISupportedInterfaceOrientations~ipad`, no `UIRequiresFullScreen`, so Split
View and Slide Over work. Once a version ships with iPad it cannot be removed.

- The home screen is the unfolded iPhone Duo layout (`.claude/rules/iphone-duo.md`):
  at regular width of at least 720 pt (every iPad portrait and landscape, and
  Split View windows that wide) the open tab (Log, Upgrade / Reports or
  Settings, capsule on top) sits on the left and History on the right, each
  pane phone-sized with `horizontalSizeClass = .compact`. Narrower windows
  (Slide Over, a third of the screen) keep the single phone screen. There is
  no separate iPad view tree, so a change to either surface shows on both.
- Log's buttons grow to `maxLogButtonHeightPad` (200) on an iPad
  (`NowView.maxButtonHeight`, `NowFit.make(maxButton:)`); at the phone cap a tall
  portrait pane left a gap above the totals. The fit logic is otherwise unchanged.
- Onboarding is one centered column of `readableWidth` (600). While it fits the
  height, an iPad centers the whole setup with its button (`ViewThatFits`);
  a phone, or a page too tall, keeps the button pinned under a scrolling form.
- Sheets (editor, sharing, stain helper, paywall) are SwiftUI's own iPad form
  sheets; nothing sizes them by hand. New sheets must not assume a bottom sheet.
- Widths: `wideLayout` 700 (Now's two-column body, for a single wide screen),
  `contentWidth` 1000 (cap on a page), `readableWidth` 600 (forms).

Verification (no iPad pool device holds 13 inch, so use GitHub's): `gh-sim launch
--device "iPad Pro 13-inch (M5)"` with `-SeedScreenshotData -NoCloudKit -DemoPro
-DuoStop <log|calendar|weeks|reports|settings|firstweeks|night>`; check portrait
and landscape, then Slide Over width. The local pool has an 11 inch iPad Air
(`agent-sim checkout <owner> --device "iPad Air 11-inch (M4)"`; `--slot 6`
returned a phone once). A raw `simctl launch` needs `-NoCloudKit` as its own
argument, not inside a quoted string, or the unsigned build traps in CloudKit.

## Store frames

`artifacts/asc-screenshots/ipad-20261112/` composes the 13 inch set
(`APP_IPAD_PRO_3GEN_129`, 2064x2752) in the iPhone set's style and headlines:
`capture.sh` takes raw captures (Log beside History, Log beside History's
calendar, First Weeks beside History, Reports) per locale, `compose.py`
draws header and bezel and covers the simulator's clock strip. Live screenshot
locales: en-US, de-DE, es-ES, es-MX, it, pt-BR; every other storefront falls
back to en-US. `scripts/asc-upload-ipad-screenshots.py` uploads to the editable
version.
