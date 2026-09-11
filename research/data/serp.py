import json, sys, time, urllib.parse, urllib.request, statistics, datetime
terms = [l.strip() for l in open(sys.argv[1]) if l.strip()]
today = datetime.date(2026, 9, 11)
VIBE = ("rork", "vibecode", "replit", "bolt", "a0.", "lovable", "createanything", "anything.")
rows = []
for t in terms:
    url = "https://itunes.apple.com/search?" + urllib.parse.urlencode({"term": t, "country": __import__("os").environ.get("CC","us"), "entity": "software", "limit": 20})
    for attempt in range(3):
        try:
            d = json.load(urllib.request.urlopen(url, timeout=30)); break
        except Exception as e:
            time.sleep(3); d = {"results": []}
    res = d.get("results", [])[:15]
    if not res: rows.append((t, 0)); continue
    ratings = [r.get("userRatingCount", 0) for r in res]
    rel = [datetime.date.fromisoformat(r["releaseDate"][:10]) for r in res]
    upd = [datetime.date.fromisoformat(r["currentVersionReleaseDate"][:10]) for r in res]
    new12 = sum((today - x).days <= 365 for x in rel)
    vibe = sum(any(v in r.get("bundleId", "").lower() for v in VIBE) for r in res)
    stale = sum((today - x).days > 365 for x in upd[:5])
    top = sorted(ratings, reverse=True)
    paid = sum(1 for r in res if r.get("price", 0) > 0)
    rows.append((t, len(res), top[0], top[2] if len(top) > 2 else 0, int(statistics.median(ratings)), new12, vibe, stale, res[0]["trackName"][:28], ratings[0]))
    time.sleep(0.4)
print(f"{'term':28} {'n':>2} {'max':>8} {'3rd':>7} {'med':>6} {'new12':>5} {'vibe':>4} {'stale5':>6}  #1(ratings)")
for r in rows:
    if r[1] == 0: print(f"{r[0]:28} none"); continue
    print(f"{r[0]:28} {r[1]:>2} {r[2]:>8} {r[3]:>7} {r[4]:>6} {r[5]:>5} {r[6]:>4} {r[7]:>6}  {r[8]} ({r[9]})")
