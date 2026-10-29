import json, sys
sys.path.insert(0, sys.argv[1])
from corpus import CORPUS, HELD_OUT, generated, PLACES
from downloads import DOWNLOADS
APP = PLACES["lamp"]
fix = lambda items, group: [dict(c, command=c["command"].replace("{APP}", APP), folder=c.get("folder", APP), group=c.get("group", group)) for c in items]
json.dump(fix(CORPUS + HELD_OUT, "corpus"), open(f"{sys.argv[1]}/core.json", "w"), indent=1)
json.dump(fix(DOWNLOADS, "downloads"), open(f"{sys.argv[1]}/downloads.json", "w"), indent=1)
json.dump(generated(), open(f"{sys.argv[1]}/generated.json", "w"), indent=1)
