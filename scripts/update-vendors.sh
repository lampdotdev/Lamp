#!/bin/zsh
# Makes Resources/vendors.xz, the list of network hardware makers Lamp reads a device's maker from by the first
# digits of its hardware address (`Vendors`), out of the IEEE's public registry of those prefixes: MA-L (six hex
# digits), MA-M (seven) and MA-S (nine). Each line is a prefix, a tab and the maker's name with the company's legal
# ending taken off ("Espressif", not "Espressif Inc."), sorted, then compressed as xz, which Apple's Compression
# framework reads as its LZMA. Run it now and then: makers are added every week.
set -euo pipefail
cd "${0:A:h}/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# The registry turns away requests that don't look like a browser's.
agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
for list in oui/oui oui28/mam oui36/oui36; do
  curl -fsSL -A "$agent" -o "$work/${list:t}.csv" "https://standards-oui.ieee.org/$list.csv"
done
python3 -I - "$work" Resources/vendors.xz <<'EOF'
import csv, lzma, re, sys
work, out = sys.argv[1], sys.argv[2]
endings = r"(,?\s+(inc|incorporated|corp|corporation|co|company|ltd|limited|llc|l\.l\.c|gmbh|ag|s\.?a|s\.?p\.?a|b\.?v|n\.?v|"\
          r"oy|ab|as|a/s|pty|pte|plc|srl|s\.r\.l|sas|kg|co\.,? ?ltd|technologies|technology|electronics co))\.?$"
def short(name):
    name = re.sub(r"\s+", " ", name).strip().strip(",.").strip()
    for _ in range(4):
        trimmed = re.sub(endings, "", name, flags=re.I).strip().strip(",.").strip()
        if not trimmed or trimmed == name: break
        name = trimmed
    # A name the registry has in capitals reads better in the list as a name: "CANON" is Canon.
    if name.isupper() and len(name) > 4: name = " ".join(w if len(w) <= 3 else w.capitalize() for w in name.split(" "))
    return name
entries = {}
for list in ("oui", "mam", "oui36"):
    with open(f"{work}/{list}.csv", newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            prefix, name = row["Assignment"].strip().upper(), short(row["Organization Name"])
            # The private blocks name nobody, and a block sold on in smaller parts is named by those parts.
            if not re.fullmatch(r"[0-9A-F]{6}|[0-9A-F]{7}|[0-9A-F]{9}", prefix) or not name or name.lower() == "private": continue
            if name == "IEEE Registration Authority": continue
            entries[prefix] = name
text = "".join(f"{p}\t{n}\n" for p, n in sorted(entries.items()))
data = lzma.compress(text.encode("utf-8"), format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC32, preset=9 | lzma.PRESET_EXTREME)
open(out, "wb").write(data)
print(f"{len(entries)} prefixes, {len(data) // 1024} KB")
EOF
