#!/bin/zsh
# Puts three.js, the 3D library a three.js game and an Xbox web app take (DeviceSupport.Library.three), in
# Resources/WebLibraries/three: the WebGL build (three.module.js and three.core.js), the WebGPU renderer with its node
# materials (three.webgpu.js and three.tsl.js, which draw with WebGL 2 where WebGPU isn't there) and the light addons.
#
# They come from one commit of three.js's own repository, the builds it keeps in build/ and the addons in
# examples/jsm, each file checked against the git hash the repository lists for it at that commit, so what's fetched is
# exactly that commit's. A commit rather than a release: the New York starter is drawn with node materials that need a
# fix made after the last release (0.186.1). Run it to move to another commit: change the line below.
set -euo pipefail
cd "${0:A:h}/.."
commit=fae873455dff9602a916b4d2e8a985921448b62a

out=Resources/WebLibraries/three
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 -I - "$commit" "$work" <<'EOF'
import hashlib, json, os, re, sys, urllib.request
commit, work = sys.argv[1], sys.argv[2]
def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "lamp-update-three"})) as r: return r.read()
tree = json.loads(get(f"https://api.github.com/repos/mrdoob/three.js/git/trees/{commit}?recursive=1"))
if tree.get("truncated"): sys.exit("The repository's file list came back cut short.")
blobs = {t["path"]: t["sha"] for t in tree["tree"] if t["type"] == "blob"}
builds = ["build/three.module.js", "build/three.core.js", "build/three.webgpu.js", "build/three.tsl.js", "LICENSE"]
folders = ["animation", "controls", "curves", "effects", "environments", "geometries", "helpers", "interactive", "lights",
           "lines", "loaders", "math", "misc", "modifiers", "objects", "postprocessing", "shaders", "textures", "utils",
           "lighting", "tsl"]
libs = ["fflate.module.js", "lil-gui.module.min.js", "potpack.module.js", "stats.module.js", "tween.module.js", "meshopt_decoder.module.js"]
# Of the loaders, the formats a game or scene is made from; the rest are for CAD, science and formats needing a decoder.
loaders = ["GLTFLoader", "OBJLoader", "MTLLoader", "FBXLoader", "STLLoader", "PLYLoader", "SVGLoader", "FontLoader",
           "HDRLoader", "RGBELoader", "EXRLoader", "TGALoader", "UltraHDRLoader"]
jsm = "examples/jsm/"
files = {p[len(jsm):] for p in blobs if p.startswith(jsm) and p.endswith(".js") and p[len(jsm):].split("/")[0] in folders}
files |= {"libs/" + f for f in libs if jsm + "libs/" + f in blobs}
files = {f for f in files if not f.startswith("loaders/") or f[len("loaders/"):-3] in loaders}
def fetch(path):
    data = get(f"https://raw.githubusercontent.com/mrdoob/three.js/{commit}/{path}")
    if hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest() != blobs[path]: sys.exit(f"{path} isn't the file the commit has.")
    return data
texts = {f: fetch(jsm + f) for f in sorted(files)}
# The addons are the folders people build games and scenes with, less what needs a big decoder Lamp doesn't ship (Draco,
# Basis, KTX2): a file is kept only when every file it imports is kept too, so an import in a kept addon never fails.
imports = re.compile(r"""(?:import|export)\s[^'"]*?from\s*['"]([^'"]+)['"]|import\s*\(\s*['"]([^'"]+)['"]|import\s+['"]([^'"]+)['"]""")
def needs(path):
    # Comments go first: the addons' own doc comments show imports as examples.
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", texts[path].decode("utf-8"), flags=re.S)
    for groups in imports.findall(text):
        spec = next(g for g in groups if g)
        if spec in ("three", "three/webgpu", "three/tsl"): continue
        if spec.startswith("three/addons/"): yield os.path.normpath(spec[len("three/addons/"):]); continue
        if not spec.startswith("."): yield None; continue
        yield os.path.normpath(os.path.join(os.path.dirname(path), spec))
kept = set(files)
while True:
    dropped = {f for f in kept if any(n is None or n not in kept for n in needs(f))}
    if not dropped: break
    kept -= dropped
for f in sorted(kept):
    os.makedirs(os.path.dirname(os.path.join(work, "three/addons", f)), exist_ok=True)
    open(os.path.join(work, "three/addons", f), "wb").write(texts[f])
for b in builds: open(os.path.join(work, "three", os.path.basename(b)), "wb").write(fetch(b))
print(f"{len(kept)} addons kept of {len(files)}")
EOF
rm -rf "$out" && mv "$work/three" "$out"
cat > "$out/NOTICE.md" <<EOF
three.js at commit $commit of github.com/mrdoob/three.js (r$(grep -o "REVISION = '[^']*'" "$out/three.core.js" | cut -d"'" -f2)),
under the MIT license in LICENSE: build/three.module.js, build/three.core.js, build/three.webgpu.js and
build/three.tsl.js, and some of examples/jsm as addons/ (scripts/update-three.sh says which), each checked against the
git hash the commit lists for it.
EOF
du -sh "$out"
