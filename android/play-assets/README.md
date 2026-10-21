# Play listing assets

Layout read by `play_stage.py`: `metadata/android/en-US/` holds `title.txt`
(29 chars), `short_description.txt` (77), `full_description.txt` (about 3100,
plain text) and `release-notes.txt`. The copy moved here from `listing/`
unchanged (title is the live App Store name). Nothing claims to treat or
diagnose; the full description ends with the not-medical-advice line.

- `icon-512.png`: the existing 512x512 RGB icon, unchanged.
- `feature-graphic.svg` is the source; `feature-graphic.png` (1024x500, RGB,
  no alpha) is drawn from the same geometry with Pillow (2x, downsampled),
  because no SVG renderer is installed on jmbp2. Same four-tile art and
  colours as the icon, on its cream background, app name and one line of copy.
  No device frame.
- `screenshots/` (1080x2160, RGB, no alpha): raw captures from the debug
  build on `agent-emu-1` (API 36, Play image) with `adb exec-out screencap`.
  Status bar demo mode (10:00, full wifi and battery, no notifications).
  Launch: `am start -S -n com.jackwallner.baby/.MainActivity --ez seed true
  --ez plus true --ez screenshot true --ei tab 0 --es appearance light`
  (`night` for 05). Baby+ is the debug-only local override (`plus`), no
  production RevenueCat key is involved. Reports and the two guides were
  reached by tapping from the Log tab (the `--ei tab` extra was flaky for
  tabs 2 and 3). Seed is the day-three newborn log "Elsa".
  Order: 01 Log, 02 Reports, 03 Stain helper, 04 First Weeks, 05 Night light.
  The floating bottom bar is the app's real translucent capsule.
- Nothing here has been uploaded to Play.
