#!/bin/zsh
# Puts three.js, the 3D library an Xbox web app takes (DeviceSupport.Library.three), in Resources/WebLibraries/three:
# the WebGL build (three.module.js and three.core.js) and the light addons, from npm's package, checked against the
# SHA-512 npm publishes for it. Run it to move to another version: change the two lines below.
#
# The addons are the folders people build games and scenes with (controls, loaders, geometries, postprocessing…), less
# what needs a big decoder Lamp doesn't ship (Draco, Basis, KTX2) or the WebGPU renderer: a file is kept only when every
# file it imports is kept too, so an import in a kept addon never fails.
set -euo pipefail
cd "${0:A:h}/.."
version=0.186.1
integrity="sha512-blFeqb49wRCSGUGj7gtpfnSGHy2lwDk94RhUmS1c/hTby70kvChbWpkJ4Pm1390LqzzvTmzgXKHPEafJwCb8jA=="

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/three.tgz" "https://registry.npmjs.org/three/-/three-$version.tgz"
[[ "sha512-$(openssl dgst -sha512 -binary "$work/three.tgz" | base64)" == "$integrity" ]] || { print -u2 "three $version isn't the package npm published."; exit 1; }
mkdir "$work/x" && tar -xzf "$work/three.tgz" -C "$work/x"

out=Resources/WebLibraries/three
rm -rf "$out" && mkdir -p "$out"
cp "$work/x/package/build/three.module.js" "$work/x/package/build/three.core.js" "$work/x/package/LICENSE" "$out/"
python3 -I - "$work/x/package/examples/jsm" "$out/addons" <<'EOF'
import os, re, shutil, sys
source, target = sys.argv[1], sys.argv[2]
folders = ["animation", "controls", "curves", "effects", "environments", "geometries", "helpers", "interactive", "lights",
           "lines", "loaders", "math", "misc", "modifiers", "objects", "postprocessing", "shaders", "textures", "utils"]
libs = ["fflate.module.js", "lil-gui.module.min.js", "potpack.module.js", "stats.module.js", "tween.module.js", "meshopt_decoder.module.js"]
# Of the loaders, the formats a game or scene is made from; the rest are for CAD, science and formats needing a decoder.
loaders = ["GLTFLoader", "OBJLoader", "MTLLoader", "FBXLoader", "STLLoader", "PLYLoader", "SVGLoader", "FontLoader",
           "HDRLoader", "RGBELoader", "EXRLoader", "TGALoader", "UltraHDRLoader"]
files = {os.path.relpath(os.path.join(d, f), source) for folder in folders for d, _, fs in os.walk(os.path.join(source, folder))
         for f in fs if f.endswith(".js")} | {"libs/" + f for f in libs}
files = {f for f in files if not f.startswith("loaders/") or f[len("loaders/"):-3] in loaders}
imports = re.compile(r"""(?:import|export)\s[^'"]*?from\s*['"]([^'"]+)['"]|import\s*\(\s*['"]([^'"]+)['"]|import\s+['"]([^'"]+)['"]""")
def needs(path):
    # Comments go first: the addons' own doc comments show imports as examples.
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", open(os.path.join(source, path), encoding="utf-8").read(), flags=re.S)
    for groups in imports.findall(text):
        spec = next(g for g in groups if g)
        if spec == "three": continue
        if spec.startswith("three/addons/"): yield os.path.normpath(spec[len("three/addons/"):]); continue
        if not spec.startswith("."): yield None; continue
        yield os.path.normpath(os.path.join(os.path.dirname(path), spec))
kept = set(files)
while True:
    dropped = {f for f in kept if any(n is None or n not in kept for n in needs(f))}
    if not dropped: break
    kept -= dropped
for f in sorted(kept):
    os.makedirs(os.path.dirname(os.path.join(target, f)), exist_ok=True)
    shutil.copy(os.path.join(source, f), os.path.join(target, f))
print(f"{len(kept)} addons kept of {len(files)}")
EOF
cat > "$out/NOTICE.md" <<EOF
three.js $version, from npm (three-$version.tgz, $integrity), under the MIT licence in LICENSE.
build/three.module.js and build/three.core.js, and some of examples/jsm as addons/
(scripts/update-three.sh says which).
EOF
du -sh "$out"
