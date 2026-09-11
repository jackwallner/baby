import json, re, sys, time, urllib.parse, urllib.request, html
def search(term, n=3):
    url = "https://itunes.apple.com/search?" + urllib.parse.urlencode({"term": term, "country": "us", "entity": "software", "limit": n})
    return json.load(urllib.request.urlopen(url, timeout=30))["results"][:n]
def ladder(app_id):
    req = urllib.request.Request(f"https://apps.apple.com/us/app/id{app_id}", headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15", "Accept-Language": "en-US"})
    page = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "ignore")
    i = page.find("In-App Purchases")
    if i < 0: return "no IAP"
    seg = html.unescape(re.sub(r"<[^>]+>", "|", page[i:i+6000]))
    seg = re.sub(r"\|+", "|", seg)
    prices = re.findall(r"\|([^|]{2,60})\|\s*\$([\d.,]+)", seg)
    return "; ".join(f"{n.strip()} ${p}" for n, p in prices[:8]) or seg[:300]
for term in sys.argv[1:]:
    for r in search(term):
        try: l = ladder(r["trackId"])
        except Exception as e: l = f"err {e}"
        print(f"[{term}] {r['trackName'][:34]} ({r.get('userRatingCount',0)}) rel {r['releaseDate'][:7]} :: {l}")
        time.sleep(0.5)
