# Screenshot localization kit

```sh
cd l10n-kit
/usr/bin/python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
./build.sh
# Downloads shallow public clones, tests real frames, writes all seven locales,
# roundtrip.png, comparison sheets, and verifies planted gate failures.
OPENBLAS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 python -u tests/verify.py

# Repeat the four bezel detections and cropped-screen NCC round trips:
for app in bridge quitzyn; do
  for frame in .work/$app/fastlane/screenshots/en-US/0[12]*.png; do
    python locate.py "$frame" --bezel --radius
    python locate.py "$frame" ".work/$app-$(basename "$frame" .png)-raw.png" --radius
  done
done

python reskin.py --config roundtrip.json --raw-root .work/roundtrip-raw --headers roundtrip-headers.json --locale en-US --out .work/roundtrip
for locale in de ar th hi ru vi ja; do
  python reskin.py --config frames.json --raw-root .work/raw --headers headers.json --locale "$locale" --out samples
  python sheet.py --config frames.json --locale "$locale" --out-root samples --base-label en
  python gate.py --config frames.json --raw-root .work/raw --headers headers.json --out-root samples --locale "$locale"
done
# Optional: --set phone on reskin; English leak OCR on every raw:
python gate.py --config frames.json --raw-root .work/raw --headers headers.json --out-root samples --locale de --catalog Localizable.xcstrings --lang de

printf '%s\n' '[{"text":"اختر المزايدة\nالافتتاحية","locale":"ar","font":"AvenirNextCondensed-Bold","color":[24,40,32],"box":[1240,410],"maxSize":156,"minSize":60,"align":"left","out":"header.png"}]' | ./headline
printf '%s\n' '[{"path":"capture.png","languages":["en-US"]}]' | ./ocr
```

Edit `frames.json` and `headers.json` for each app. Config image paths are relative to the config file. Rectangles use `[x,y,w,h]` in canvas pixels; radius is also in canvas pixels. A photo `plate` must match the full canvas. Keep background pixels immediately outside both header sides; otherwise supply a plate.

Put raws at `RAW_ROOT/LOCALE/SET/RAW.png`, including English references at `en-US` (override with config `english_locale`). Outputs go to `OUT_ROOT/LOCALE/SET/file.png`; sheets go to `OUT_ROOT/sheets/LOCALE-SET.jpg`. Keep the output root app-specific.

Use `--bezel` for a continuous dark bezel with visible top and bottom; use RAW for clipped devices. Default minimum score is 0.65. `--radius` adds the estimated radius; bezel mode reports scale 1 in frame pixels.

Run `build.sh` on each host to compile native binaries (macOS 12+, Swift 5.7+). The included iPad example uses a real Bridge native capture as its canvas. Sample screen content is synthetic.
