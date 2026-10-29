#!/usr/bin/env python3 -I
"""Writes Resources/asset-catalog.json: Lamp's index of free models, sprites, tiles, icons and textures the agent can
bring into an app with the `assets` tool (`AssetCatalog` in Sources/Lamp). Lamp ships the index, never the assets: each
entry says where its file is, and Lamp fetches it into the app when the agent chooses it.

Only work anyone may use without asking is listed: CC0, or CC-BY, whose credit Lamp records in the app's credits.json.
Every license is read from where the file is published (each model's own page on Poly Pizza, each pack's page on
OpenGameArt, ambientCG's API and license page); anything that says another license (non-commercial, no derivatives,
share-alike, "personal use", none) is left out, and the run says what it left out and why. Every file is downloaded and
pinned by its SHA-256, so Lamp fetches exactly what was checked here; a file changed at its source since is refused until
this is run again. Models are read for what the agent needs to choose and place one: triangles, its box in meters (y up,
as glTF has it), its textures' largest side, its animations, and that it needs no decoder three.js lacks here (Draco,
meshopt, KTX2 are refused).

Run it to refresh the index, or after changing the lists below. Downloads are kept in a cache folder (the first argument,
or a new temporary folder), so a second run after a small change is quick. Needs nothing but Python 3.
"""
import concurrent.futures, hashlib, io, json, math, os, re, struct, subprocess, sys, tempfile, time, urllib.parse, zipfile

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "asset-catalog.json")
AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

# The licenses Lamp lists, as each source writes them, by SPDX id. Anything else is left out.
LICENSES = {"CC0 1.0": "CC0-1.0", "CC0": "CC0-1.0", "CC-BY 3.0": "CC-BY-3.0", "CC-BY 4.0": "CC-BY-4.0",
            "CC-BY 3.0 Unported": "CC-BY-3.0", "CC-BY 4.0 International": "CC-BY-4.0"}

# MARK: What's listed

# Poly Pizza bundles: whole packs by one author, each model's license read from its own page.
# (bundle id on poly.pizza, pack id, name, author's own page, kind, style)
POLY_BUNDLES = [
    ("City-Kit-0CkvGrBJ0u", "kenney-city", "City Kit", "https://kenney.nl/assets/city-kit-commercial", "building",
     "Kenney: low-poly, flat colors, a tile is 1 unit"),
    ("Suburban-Houses-Pack-dZQwy8vcDv", "kenney-suburban", "Suburban Houses", "https://kenney.nl/assets/city-kit-suburban", "building",
     "Kenney: low-poly, flat colors"),
    ("Furniture-Kit-NoG1sEUD1z", "kenney-furniture", "Furniture Kit", "https://kenney.nl/assets/furniture-kit", "prop",
     "Kenney: low-poly, flat colors"),
    ("Survival-Kit-yGnSPFp2lH", "kenney-survival", "Survival Kit", "https://kenney.nl/assets/survival-kit", "prop",
     "Kenney: low-poly, flat colors"),
    ("Space-Kit-M8xXmqhHiU", "kenney-space", "Space Kit", "https://kenney.nl/assets/space-kit", "prop",
     "Kenney: low-poly, flat colors"),
    ("City-Builder-Bits-1wLdnIddSx", "kaykit-city", "City Builder Bits", "https://kaylousberg.com", "building",
     "KayKit: chunky low-poly, soft pastel colors"),
    ("Cars-Bundle-FE5IWe6OMk", "quaternius-cars", "Cars Bundle", "https://quaternius.com", "vehicle",
     "Quaternius: low-poly, flat colors"),
    ("Modular-Train-Pack-jYEybkFVr1", "quaternius-train", "Modular Train Pack", "https://quaternius.com", "vehicle",
     "Quaternius: low-poly, flat colors"),
    ("Animated-Tank-Pack-0tfvbeAJkU", "quaternius-tanks", "Animated Tank Pack", "https://quaternius.com", "vehicle",
     "Quaternius: low-poly, flat colors, animated"),
    ("Stylized-Nature-MegaKit-T34GZFA0fm", "quaternius-nature", "Stylized Nature MegaKit", "https://quaternius.com", "nature",
     "Quaternius: stylized low-poly, soft shading"),
    ("Ultimate-Platformer-Pack-cVxJUWO3nC", "quaternius-platformer", "Ultimate Platformer Pack", "https://quaternius.com", "prop",
     "Quaternius: low-poly, bright toy colors"),
    ("Medieval-Village-Pack-NsHhjhlrfY", "quaternius-medieval", "Medieval Village Pack", "https://quaternius.com", "building",
     "Quaternius: low-poly, flat colors"),
    ("Farm-Buildings-Bundle-ppbnhEfNEt", "quaternius-farm", "Farm Buildings", "https://quaternius.com", "building",
     "Quaternius: low-poly, flat colors"),
    ("Animated-Animal-Pack-ILAPXeUYiS", "quaternius-animals", "Animated Animal Pack", "https://quaternius.com", "character",
     "Quaternius: low-poly, flat colors, rigged and animated"),
    ("Farm-Animal-Pack-1kUvRTPLzT", "quaternius-farm-animals", "Farm Animal Pack", "https://quaternius.com", "character",
     "Quaternius: low-poly, flat colors, rigged and animated"),
    ("Ultimate-Modular-Men-Pack-ZiH8muWqwQ", "quaternius-men", "Ultimate Modular Men", "https://quaternius.com", "character",
     "Quaternius: low-poly people, rigged and animated"),
    ("Ultimate-Modular-Women-Pack-aCBDXDdTNN", "quaternius-women", "Ultimate Modular Women", "https://quaternius.com", "character",
     "Quaternius: low-poly people, rigged and animated"),
    ("Ultimate-Monsters-Bundle-5oyGWAmOB6", "quaternius-monsters", "Ultimate Monsters", "https://quaternius.com", "character",
     "Quaternius: cute low-poly creatures, rigged and animated"),
    ("Toon-Shooter-Game-Kit-qraiSXoAru", "quaternius-shooter", "Toon Shooter Game Kit", "https://quaternius.com", "prop",
     "Quaternius: toon low-poly"),
    ("Ultimate-Space-Kit-YWh743lqGX", "quaternius-space", "Ultimate Space Kit", "https://quaternius.com", "prop",
     "Quaternius: low-poly, flat colors"),
]

# Single models found by a search on Poly Pizza, from authors whose work there is consistent, for what packs lack (a
# taxi, a bus, a traffic light). Poly by Google's are CC-BY: they're listed so a game can have them, credited.
# (query, kind, how many at most)
POLY_SEARCHES = [
    ("car", "vehicle", 8), ("taxi", "vehicle", 4), ("bus", "vehicle", 4), ("truck", "vehicle", 4),
    ("police car", "vehicle", 2), ("ambulance", "vehicle", 2), ("fire truck", "vehicle", 2),
    ("traffic light", "prop", 4), ("street light", "prop", 4), ("bench", "prop", 2), ("fire hydrant", "prop", 2),
    ("person", "character", 6), ("tree", "nature", 4),
]
POLY_AUTHORS = {"Quaternius", "Kenney", "Kay Lousberg", "Poly by Google"}
POLY_STYLES = {"Quaternius": "Quaternius: low-poly, flat colors", "Kenney": "Kenney: low-poly, flat colors",
               "Kay Lousberg": "KayKit: chunky low-poly, soft pastel colors", "Poly by Google": "Google Poly: low-poly, flat colors"}

# Kenney's 2D packs as he published them on OpenGameArt (his own site hands out short-lived links). Each lists the
# files worth bringing in: sprite sheets with their XML atlases (Phaser's `load.atlasXML` reads them as they are),
# tilesheets with their tile size and spacing, and single pictures where an app wants one at a time (icons).
# (page, pack id, name, kind, style, [assets: (name, kind, [files], notes)], [(glob, kind, notes) for one asset per file])
OGA_PACKS = [
    ("platformer-pack-redux-360-assets", "kenney-platformer", "Platformer Pack Redux", "sprites",
     "Kenney: clean cartoon vector, 128 px tiles", [
         ("Players", "sprites", ["Spritesheets/spritesheet_players.png", "Spritesheets/spritesheet_players.xml"], "five aliens: stand, walk, jump, climb, duck, hurt"),
         ("Enemies", "sprites", ["Spritesheets/spritesheet_enemies.png", "Spritesheets/spritesheet_enemies.xml"], "slimes, bees, snails, fish and more, two frames each"),
         ("Tiles", "tileset", ["Spritesheets/spritesheet_tiles.png", "Spritesheets/spritesheet_tiles.xml"], "128 px platform tiles: boxes, bridges, ladders, spikes, water, lava"),
         ("Ground", "tileset", ["Spritesheets/spritesheet_ground.png", "Spritesheets/spritesheet_ground.xml"], "128 px ground in grass, dirt, sand, snow, stone, planet"),
         ("Items", "sprites", ["Spritesheets/spritesheet_items.png", "Spritesheets/spritesheet_items.xml"], "coins, gems, keys, flags, springs, switches"),
         ("HUD", "ui", ["Spritesheets/spritesheet_hud.png", "Spritesheets/spritesheet_hud.xml"], "hearts, coins, keys, digits"),
     ], []),
    ("space-shooter-redux", "kenney-space-shooter", "Space Shooter Redux", "sprites", "Kenney: clean cartoon vector", [
        ("Ships, lasers and meteors", "sprites", ["Spritesheet/sheet.png", "Spritesheet/sheet.xml"], "player ships, enemies, lasers, meteors, power-ups, effects, UI"),
    ], []),
    ("racing-pack", "kenney-racing", "Racing Pack", "sprites", "Kenney: top-down cartoon vector", [
        ("Cars", "sprites", ["Spritesheets/spritesheet_vehicles.png", "Spritesheets/spritesheet_vehicles.xml"], "top-down cars and motorcycles in five colors"),
        ("Track tiles", "tileset", ["Spritesheets/spritesheet_tiles.png", "Spritesheets/spritesheet_tiles.xml"], "top-down road, grass, sand and dirt tiles"),
        ("Track objects", "sprites", ["Spritesheets/spritesheet_objects.png", "Spritesheets/spritesheet_objects.xml"], "cones, barriers, tires, trees, tribunes"),
        ("Drivers", "sprites", ["Spritesheets/spritesheet_characters.png", "Spritesheets/spritesheet_characters.xml"], "top-down people"),
    ], []),
    ("tiny-town", "kenney-tiny-town", "Tiny Town", "tileset", "Kenney: 16 px pixel art", [
        ("Town tiles", "tileset", ["Tilemap/tilemap_packed.png"], "16x16 px tiles, no spacing (12 by 11): grass, paths, houses, fences, trees"),
    ], []),
    ("tiny-dungeon", "kenney-tiny-dungeon", "Tiny Dungeon", "tileset", "Kenney: 16 px pixel art", [
        ("Dungeon tiles", "tileset", ["Tilemap/tilemap_packed.png"], "16x16 px tiles, no spacing (12 by 11): walls, floors, heroes, monsters, items"),
    ], []),
    ("roguelikerpg-pack-1700-tiles", "kenney-roguelike", "Roguelike/RPG Pack", "tileset", "Kenney: 16 px pixel art", [
        ("Roguelike tiles", "tileset", ["Spritesheet/roguelikeSheet_transparent.png"], "16x16 px tiles with 1 px spacing: terrain, buildings, furniture, plants"),
    ], []),
    ("rpg-urban-pack", "kenney-rpg-urban", "RPG Urban Pack", "tileset", "Kenney: 16 px pixel art", [
        ("Urban tiles", "tileset", ["Tilemap/tilemap_packed.png"], "16x16 px tiles, no spacing (27 by 18): streets, cars, buildings, people"),
    ], []),
    ("toon-characters-1", "kenney-toon-characters", "Toon Characters", "sprites", "Kenney: cartoon vector characters", [
        ("Robot", "sprites", ["Robot/Tilesheet/character_robot_sheet.png", "Robot/Tilesheet/character_robot_sheet.xml"], "poses: idle, walk, run, jump, climb, hurt, attack"),
        ("Zombie", "sprites", ["Zombie/Tilesheet/character_zombie_sheet.png", "Zombie/Tilesheet/character_zombie_sheet.xml"], "poses: idle, walk, run, jump, climb, hurt, attack"),
    ], []),
    ("animal-pack-redux", "kenney-animals", "Animal Pack Redux", "sprites", "Kenney: round cartoon animal faces", [
        ("Round animals", "sprites", ["Spritesheet/round.png", "Spritesheet/round.xml"], "30 animal heads, round"),
        ("Square animals", "sprites", ["Spritesheet/square.png", "Spritesheet/square.xml"], "30 animal heads, square"),
    ], []),
    ("ui-pack", "kenney-ui", "UI Pack", "ui", "Kenney: flat rounded UI", [], [
        (r"PNG/Blue/Default/[^/]+\.png", "ui", "blue buttons, panels, sliders, checkboxes, arrows"),
    ]),
    ("game-icons", "kenney-game-icons", "Game Icons", "icons", "Kenney: flat white icons", [
        ("Game icons sheet", "icons", ["Spritesheet/sheet_white2x.png", "Spritesheet/sheet_white2x.xml"], "105 white icons, 100 px"),
    ], [
        (r"PNG/White/2x/[^/]+\.png", "icons", "white icon, 100 px"),
    ]),
]

# ambientCG's materials: each a set of maps at 1K (color, normal for OpenGL, roughness), for floors, walls and ground.
AMBIENTCG = ["Asphalt026C", "Bricks090", "Concrete034", "Grass004", "Ground054", "Gravel022", "PavingStones138",
             "Planks037B", "WoodFloor051", "Tiles074", "Rock030", "RoofingTiles014B", "Fabric026", "Metal032", "Ground080"]

# MARK: Fetching

def cache_path(cache, url):
    return os.path.join(cache, hashlib.sha256(url.encode()).hexdigest()[:24] + os.path.splitext(urllib.parse.urlparse(url).path)[1][:8])

def get(url, cache):
    """A file from the web, by curl (which uses the Mac's own certificates), kept in the cache."""
    path = cache_path(cache, url)
    if not os.path.exists(path):
        subprocess.run(["/usr/bin/curl", "-fsSL", "--retry", "4", "--max-time", "300", "-A", AGENT, "-o", path + ".part", url], check=True)
        os.replace(path + ".part", path)
    return open(path, "rb").read()

def state(html):
    """The data Poly Pizza's page is drawn from."""
    match = re.search(r"window.__SERVER_APP_STATE__ =\s*(\{.*?\})\s*</script>", html, re.S)
    if not match: raise RuntimeError("Poly Pizza's page has no state: its layout has changed.")
    return json.loads(match.group(1))["initialData"]

# MARK: Reading a model

def glb_facts(data):
    """Triangles, box, textures and animations of a .glb, or the reason it can't be used here."""
    if len(data) < 20 or data[:4] != b"glTF": return None, "not a binary glTF"
    length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + length])
    needs = set(gltf.get("extensionsRequired", []) + gltf.get("extensionsUsed", []))
    missing = needs & {"KHR_draco_mesh_compression", "EXT_meshopt_compression", "KHR_texture_basisu"}
    if missing: return None, "needs " + ", ".join(sorted(missing))
    accessors = gltf.get("accessors", [])
    triangles = 0
    for mesh in gltf.get("meshes", []):
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4: continue
            source = primitive.get("indices", primitive["attributes"].get("POSITION"))
            if source is not None: triangles += accessors[source]["count"] // 3
    # The box, through each node's transform, in the units the file has (meters, by glTF's convention).
    low, high = [math.inf] * 3, [-math.inf] * 3
    def matrix(node):
        if "matrix" in node:
            m = node["matrix"]; return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
        t = node.get("translation", [0, 0, 0]); x, y, z, w = node.get("rotation", [0, 0, 0, 1]); s = node.get("scale", [1, 1, 1])
        r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
             [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
             [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
        return [[r[i][0] * s[0], r[i][1] * s[1], r[i][2] * s[2], t[i]] for i in range(3)] + [[0, 0, 0, 1]]
    def times(a, b): return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
    def visit(index, parent, depth=0):
        if depth > 64: return
        node = gltf["nodes"][index]; world = times(parent, matrix(node))
        if "mesh" in node:
            for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
                position = accessors[primitive["attributes"]["POSITION"]] if "POSITION" in primitive["attributes"] else None
                if not position or "min" not in position: continue
                for corner in range(8):
                    p = [position["max"][i] if corner >> i & 1 else position["min"][i] for i in range(3)]
                    q = [sum(world[i][k] * p[k] for k in range(3)) + world[i][3] for i in range(3)]
                    for i in range(3): low[i] = min(low[i], q[i]); high[i] = max(high[i], q[i])
        for child in node.get("children", []): visit(child, world, depth + 1)
    identity = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    scene = gltf.get("scenes", [{}])[gltf.get("scene", 0)] if gltf.get("scenes") else {"nodes": list(range(len(gltf.get("nodes", []))))}
    for root in scene.get("nodes", []): visit(root, identity)
    box = [round(v, 2) for v in low + high] if low[0] != math.inf else None
    # The largest side of its pictures, read from each one's header.
    largest = 0
    binary = data[20 + length + 8:] if len(data) > 20 + length + 8 else b""
    for image in gltf.get("images", []):
        if "bufferView" not in image: continue
        view = gltf["bufferViews"][image["bufferView"]]
        picture = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
        largest = max(largest, *(picture_size(picture) or (0, 0)))
    animations = [a.get("name") or f"animation {i}" for i, a in enumerate(gltf.get("animations", []))]
    return {"tris": triangles, "box": box, "texture": largest, "animations": animations}, None

def picture_size(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n": return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF: i += 1; continue
            marker = data[i + 1]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", data[i + 5:i + 9]); return w, h
            i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    return None

def slug(text):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", text.lower())).strip("-") or "asset"

# MARK: The sources

left_out = []

def poly_entry(listed, kind, cache):
    """A model as Poly Pizza lists it (in a bundle or a search), with its license as Poly Pizza states it for that model."""
    title, author = listed["title"].strip(), listed["creator"]["username"]
    # Poly Pizza's own field is spelled "licence".
    license = LICENSES.get(listed.get("licence") or "")
    if not license:
        left_out.append(f"{title} by {author}: {listed.get('licence') or 'no license'}"); return None
    resource = re.fullmatch(r"https://static\.poly\.pizza/([0-9a-f-]{36})\.webp", listed["previewUrl"])
    if not resource:
        left_out.append(f"{title} by {author}: no file"); return None
    url = f"https://static.poly.pizza/{resource.group(1)}.glb"
    data = get(url, cache)
    facts, refusal = glb_facts(data)
    if refusal:
        left_out.append(f"{title} by {author}: {refusal}"); return None
    # A model far from its own origin, or thousands of units across, is a piece cut from a scene: it can't be placed
    # or scaled by its box, so it isn't listed.
    box = facts["box"]
    if not box: left_out.append(f"{title} by {author}: no shape"); return None
    size = max(box[3] - box[0], box[4] - box[1], box[5] - box[2])
    center = max(abs(box[0] + box[3]), abs(box[2] + box[5])) / 2
    if size > 500 or center > size:
        left_out.append(f"{title} by {author}: {round(size)} units across, {round(center)} from its origin"); return None
    # Its picture is beside its file on Poly Pizza (the same name, .webp), so it isn't written again.
    return {"name": title, "kind": classify(title, kind), "file": url, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "page": f"https://poly.pizza{listed['url']}", "author": author, "license": license,
            **{k: v for k, v in facts.items() if v}}

def classify(title, kind):
    """What a model is, by its name where that says more than where it was found (a hydrant found by "fire truck")."""
    words = set(re.findall(r"[a-z]+", title.lower()))
    if words & {"tree", "trees", "bush", "rock", "rocks", "plant", "flower", "flowers", "grass", "mushroom", "stump", "log", "cactus", "fern"}: return "nature"
    if words & {"hydrant", "light", "streetlight", "lamp", "bench", "sign", "cone", "barrier", "post", "bin", "mailbox"}: return "prop"
    return kind

def poly_packs(cache):
    packs = []
    pool = concurrent.futures.ThreadPoolExecutor(4)
    for bundle, pack, name, home, kind, style in POLY_BUNDLES:
        listing = state(get(f"https://poly.pizza/bundle/{bundle}", cache).decode("utf-8", "replace"))["list"]
        entries = [e for e in pool.map(lambda m: poly_entry(m, kind, cache), listing["Models"]) if e]
        authors = {e["author"] for e in entries}
        if len(authors) != 1: raise RuntimeError(f"{name} has models by {sorted(authors)}: a pack is one author's.")
        packs.append({"id": pack, "name": name, "author": authors.pop(), "source": f"https://poly.pizza/bundle/{bundle}",
                      "home": home, "kind": kind, "style": style, "credit": "pack", "assets": name_assets(pack, entries)})
        print(f"{name}: {len(entries)} of {len(listing['Models'])}", file=sys.stderr)
    # Singles, found by searching, grouped by author.
    seen, singles = {a["page"] for p in packs for a in p["assets"]}, {}
    for query, kind, most in POLY_SEARCHES:
        found = state(get(f"https://poly.pizza/search/{urllib.parse.quote(query)}", cache).decode("utf-8", "replace"))["result"]
        taken = 0
        for result in found:
            if taken >= most: break
            if result["creator"]["username"] not in POLY_AUTHORS or f"https://poly.pizza{result['url']}" in seen: continue
            entry = poly_entry(result, kind, cache)
            if not entry: continue
            seen.add(entry["page"]); taken += 1
            singles.setdefault(entry["author"], []).append(entry)
    for author, entries in sorted(singles.items()):
        pack = "poly-" + slug(author)
        packs.append({"id": pack, "name": f"Models by {author}", "author": author, "source": f"https://poly.pizza/u/{urllib.parse.quote(author)}",
                      "kind": "model", "style": POLY_STYLES[author], "credit": "asset", "assets": name_assets(pack, entries)})
    return packs

def oga_packs(cache):
    packs = []
    for page, pack, name, kind, style, sheets, singles in OGA_PACKS:
        html = get(f"https://opengameart.org/content/{page}", cache).decode("utf-8", "replace")
        licenses = re.findall(r"<div class='license-name'>([^<]+)</div>", html)
        if [LICENSES.get(l) for l in licenses] != ["CC0-1.0"]:
            left_out.append(f"{name}: {licenses or 'no license'}"); continue
        author = re.search(r'field-name-author-submitter.*?<a href="/users/([^"]+)"', html, re.S).group(1)
        archive = sorted(set(re.findall(r'https://opengameart.org/sites/default/files/[^"]+\.zip', html)))[0]
        preview = next(iter(re.findall(r'https://opengameart.org/sites/default/files/(?:styles/medium/public/)?[^"]*[Pp]review[^"]*\.png', html)), None)
        data = get(archive, cache)
        members = zipfile.ZipFile(io.BytesIO(data))
        sizes = {i.filename: i.file_size for i in members.infolist()}
        # The pack's own license file says CC0 too.
        license_file = next((n for n in sizes if re.fullmatch(r"(?i)licen[cs]e\.txt", os.path.basename(n))), None)
        if not license_file or "CC0" not in members.read(license_file).decode("utf-8", "replace"):
            left_out.append(f"{name}: its own license file doesn't say CC0"); continue
        assets = []
        for title, asset_kind, files, notes in sheets:
            for f in files:
                if f not in sizes: raise RuntimeError(f"{name} has no {f}: the pack has changed.")
            png = next(f for f in files if f.endswith(".png"))
            width, height = picture_size(members.read(png))
            assets.append({"name": title, "kind": asset_kind, "files": files, "bytes": sum(sizes[f] for f in files),
                           "pixels": [width, height], "atlas": "xml" if any(f.endswith(".xml") for f in files) else None, "notes": notes})
        for pattern, asset_kind, notes in singles:
            for f in sorted(n for n in sizes if re.fullmatch(pattern, n)):
                width, height = picture_size(members.read(f))
                assets.append({"name": os.path.splitext(os.path.basename(f))[0].replace("_", " "), "kind": asset_kind, "files": [f],
                               "bytes": sizes[f], "pixels": [width, height], "notes": notes})
        for a in assets:
            if not a.get("atlas"): a.pop("atlas", None)
        packs.append({"id": pack, "name": name, "author": "Kenney" if author.lower() == "kenney" else author,
                      "source": f"https://opengameart.org/content/{page}", "home": "https://kenney.nl", "kind": kind, "style": style,
                      "license": "CC0-1.0", "credit": "pack", "thumb": preview,
                      "archive": {"url": archive, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)},
                      "assets": name_assets(pack, assets)})
        print(f"{name}: {len(assets)}", file=sys.stderr)
    return packs

def ambientcg_pack(cache):
    license = get("https://docs.ambientcg.com/license/", cache).decode("utf-8", "replace")
    if "CC0" not in license: left_out.append("ambientCG: its license page no longer says CC0"); return None
    assets = []
    for asset_id in AMBIENTCG:
        info = json.loads(get(f"https://ambientcg.com/api/v2/full_json?id={asset_id}&include=downloadData,imageData,displayData", cache))
        if not info.get("foundAssets"): left_out.append(f"{asset_id}: not on ambientCG any more"); continue
        found = info["foundAssets"][0]
        download = next(d for d in found["downloadFolders"]["default"]["downloadFiletypeCategories"]["zip"]["downloads"] if d["attribute"] == "1K-JPG")
        data = get(download["downloadLink"], cache)
        names = zipfile.ZipFile(io.BytesIO(data)).namelist()
        files = [n for n in names if re.search(r"_(Color|NormalGL|Roughness)\.jpg$", n)]
        if len(files) < 2: left_out.append(f"{asset_id}: no color and normal maps"); continue
        sizes = {i.filename: i.file_size for i in zipfile.ZipFile(io.BytesIO(data)).infolist()}
        assets.append({"name": found["displayName"], "kind": "texture", "files": sorted(files), "bytes": sum(sizes[f] for f in files),
                       "pixels": [1024, 1024], "tags": [t.lower() for t in found.get("tags", [])][:8],
                       "thumb": found.get("previewImage", {}).get("256-PNG"), "page": f"https://ambientcg.com/view?id={asset_id}",
                       "archive": {"url": download["downloadLink"], "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)},
                       "notes": "1K maps: color, normal (OpenGL), roughness; tile it with texture.repeat"})
        print(f"ambientCG {asset_id}", file=sys.stderr)
    return {"id": "ambientcg", "name": "ambientCG materials", "author": "ambientCG (Lennart Demes)", "source": "https://ambientcg.com",
            "kind": "texture", "style": "photographed, tileable PBR", "license": "CC0-1.0", "credit": "pack", "assets": name_assets("ambientcg", assets)}

def name_assets(pack, assets):
    used = set()
    for a in assets:
        base = slug(a["name"]); name, n = base, 2
        while name in used: name, n = f"{base}-{n}", n + 1
        used.add(name); a["id"] = f"{pack}/{name}"
    return assets

def check_homes(cache):
    """The authors' own pages say their work is CC0, as Poly Pizza does."""
    for url, words in [("https://kenney.nl/assets/city-kit-commercial", "CC0"), ("https://quaternius.com/faq.html", "CC0")]:
        if words not in get(url, cache).decode("utf-8", "replace"): raise RuntimeError(f"{url} no longer says {words}.")

def main():
    cache = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="lamp-assets-")
    os.makedirs(cache, exist_ok=True)
    check_homes(cache)
    packs = poly_packs(cache) + oga_packs(cache)
    textures = ambientcg_pack(cache)
    if textures: packs.append(textures)
    # A pack's license is its assets' when they share one; otherwise each asset keeps its own.
    for pack in packs:
        licenses = {a.get("license", pack.get("license")) for a in pack["assets"]}
        if len(licenses) == 1:
            pack["license"] = licenses.pop()
            for a in pack["assets"]: a.pop("license", None)
        authors = {a.get("author", pack["author"]) for a in pack["assets"]}
        if authors == {pack["author"]}:
            for a in pack["assets"]: a.pop("author", None)
    catalog = {"version": 1, "refreshed": time.strftime("%Y-%m-%d"), "licenses": sorted(set(LICENSES.values())), "packs": packs}
    # One line per asset, so a refresh reads as a diff of what changed.
    lines = ["{", f'  "version": 1, "refreshed": {json.dumps(catalog["refreshed"])},', f'  "licenses": {json.dumps(catalog["licenses"])},', '  "packs": [']
    for i, pack in enumerate(packs):
        head = {k: v for k, v in pack.items() if k != "assets"}
        lines.append("    " + json.dumps(head, ensure_ascii=False)[:-1] + ', "assets": [')
        lines += ["      " + json.dumps(a, ensure_ascii=False) + ("," if j < len(pack["assets"]) - 1 else "") for j, a in enumerate(pack["assets"])]
        lines.append("    ]}" + ("," if i < len(packs) - 1 else ""))
    lines += ["  ]", "}"]
    with open(OUT, "w") as f: f.write("\n".join(lines) + "\n")
    json.load(open(OUT))
    count = sum(len(p["assets"]) for p in packs)
    print(f"{count} assets in {len(packs)} packs, {os.path.getsize(OUT) // 1024} KB. Left out:", file=sys.stderr)
    for line in left_out: print("  " + line, file=sys.stderr)

if __name__ == "__main__":
    main()
