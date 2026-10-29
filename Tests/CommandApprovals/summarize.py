import json, sys, collections
D = sys.argv[1]
def load(side, name): return json.load(open(f"{D}/results/{side}-{name}.json"))
out = []
for name in ["downloads", "core", "generated"]:
    items = {c["id"]: c for c in json.load(open(f"{D}/{name}.json"))}
    out.append(f"\n## {name}\n")
    for side in ["before", "after"]:
        res = load(side, name)
        tally = collections.Counter()
        escapes, cards = [], []
        for id, runs in res.items():
            c = items[id]
            cls = "gap" if c["kind"] == "gap" else ("confined" if c.get("confined") else c["expect"])
            for path in ["pi", "fallback"]:
                got = [r[path] for r in runs if path in r]
                n_run = got.count("run")
                tally[(cls, path, "runs")] += n_run; tally[(cls, path, "total")] += len(got)
                if cls == "ask" and n_run: escapes.append(f"{path}: {id} ran {n_run}/{len(got)}")
                if cls == "run" and n_run < len(got): cards.append(f"{path}: {id} carded {len(got)-n_run}/{len(got)}")
        out.append(f"**{side}**")
        for cls in ["run", "ask", "gap", "confined"]:
            for path in ["pi", "fallback"]:
                t = tally[(cls, path, "total")]
                if t: out.append(f"- {cls:8} via {path:8}: ran {tally[(cls, path, 'runs')]}/{t}")
        out.append("  must-ask escapes: " + ("; ".join(escapes) if escapes else "none"))
        out.append("  should-run carded: " + ("; ".join(sorted(cards)[:40]) if cards else "none"))
    if name == "downloads":
        out.append("\nPer command, pi path (before -> after), levels after:")
        b, a = load("before", name), load("after", name)
        for id in items:
            f = lambda r: f"{sum(x['pi']=='run' for x in r)}/{len(r)}"
            out.append(f"- {id} [{items[id]['expect']}]: {f(b[id])} -> {f(a[id])} | after: {a[id][0].get('why','')} verdict {a[id][0]['verdict']}")
print("\n".join(out))
