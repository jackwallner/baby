import json, re, time, urllib.parse, urllib.request, collections
UA={"User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15"}
def get(url): return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read().decode("utf-8","ignore")
apps={}
for term in ["baby tracker","newborn tracker","diaper tracker","breastfeeding tracker"]:
    for r in json.loads(get("https://itunes.apple.com/search?"+urllib.parse.urlencode({"term":term,"country":"us","entity":"software","limit":8})))["results"]:
        if r.get("userRatingCount",0)>3000: apps[r["trackId"]]=r
THEMES={"paywall/subscription":r"paywall|subscri|premium|pay to|charge|money|expensive|free trial|trial|\$","ads":r"\bads?\b|advert","partner sync/share":r"sync|partner|husband|wife|share|caregiver|nanny|grandma|second phone|both of us|spouse","lost data/crash":r"lost|crash|deleted|gone|wiped|won't open|freez|bug","too complicated/slow":r"complicat|too many|confus|cluttered|clunky|slow|taps|steps|hard to|overwhelm|simple","timer issues":r"timer","watch/widget":r"watch|widget|lock screen|live activit|siri","account/login":r"login|log in|account|sign in|sign up|email"}
tot=collections.Counter(); samples=collections.defaultdict(list); n=0
for tid,r in apps.items():
    page=get(f"https://apps.apple.com/us/app/id{tid}")
    watch="Apple Watch" in page
    lows=0
    for p in (1,2,3,4,5):
        try: feed=json.loads(get(f"https://itunes.apple.com/us/rss/customerreviews/page={p}/id={tid}/sortby=mostrecent/json"))
        except Exception: break
        entries=feed.get("feed",{}).get("entry",[])
        if isinstance(entries,dict): entries=[entries]
        for e in entries:
            if "im:rating" not in e: continue
            if int(e["im:rating"]["label"])>2: continue
            txt=(e["title"]["label"]+". "+e["content"]["label"])
            lows+=1; n+=1
            for th,pat in THEMES.items():
                if re.search(pat,txt,re.I):
                    tot[th]+=1
                    if len(samples[th])<4: samples[th].append(f"[{r['trackName'][:18]}] "+txt[:230].replace("\n"," "))
        time.sleep(0.3)
    print(f"{r['trackName'][:40]:40} ratings {r['userRatingCount']:>7} rel {r['releaseDate'][:4]} upd {r['currentVersionReleaseDate'][:10]} watch={watch} low-reviews-sampled={lows}")
print(f"\n{n} one/two-star recent reviews; theme counts:")
for th,c in tot.most_common(): print(f"  {th}: {c} ({100*c//max(n,1)}%)")
for th,s in samples.items():
    print(f"\n## {th}"); [print("  - "+x) for x in s]
