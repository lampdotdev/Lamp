# Asset audit before open-sourcing

A check of every picture, font, sound, 3D model, data file, library and binary the repository would publish: where
it came from, what license it carries, and what is still missing. Taken from this branch after merging `main` on
2026-10-30. Nothing was changed except this file. Only what the repo shows is used: `credits.json`, `APP.md`,
NOTICE and LICENSE files beside the files, git history (the commit that added each group and its message), code
comments that say how a picture was made, and file metadata. No source was contacted, so a license a file states is
taken as stated, not checked at its source.

Since the first version of this report, `main` moved the starters out of this repo: each is now its own public
repository under the `lampdotdev` account, pinned by commit in `Resources/Starters/<name>/starter.md` and fetched at
build time (`scripts/fetch-starters.sh`). Most of the site's pictures and the onboarding film were removed. This
version audits both this repo and the 15 starter repos at the commits Lamp pins.

Verdicts used in every table:

- **Fine**: origin is clear and any license that applies is in place, or it is Lamp's own work.
- **Notice**: origin is clear, but a license file, credit or marking is missing or incomplete.
- **Unknown**: the repo does not say where it came from; the team decides.

## Counts

Files counted are pictures, icons, fonts, sounds, models, data, libraries and binaries. Source code, `APP.md`,
`about.json`, `icon.json`, `starter.md`, showcase scripts and `Tests/` are not counted.

| Verdict | This repo | The 15 starter repos | Total |
| --- | ---: | ---: | ---: |
| Fine | 407 | 311 | 718 |
| Notice | 178 | 47 | 225 |
| Unknown | 4 | 0 | 4 |

## Findings that cut across everything

1. **No picture is marked as made with AI.** All 15 starters have a `credits.json` (it holds the chain of wishes each
   was remixed from), and none has a `generated` list. About 186 pictures were made with image models: 169 on the
   site and 17 in starters (below). The repo says so in code comments, commit messages and
   `site/scripts/idea-art/README.md`, but not where Lamp's own mechanism (`generated`) looks.
2. **The starters are already public and MIT.** Every starter repo has a `LICENSE` ("MIT License, Copyright (c) 2026
   Roo Code, Inc."), including Hot Shelf, which holds CC BY-SA photos, and New York, which holds ODbL-derived data.
   A fix to a starter is a commit to that starter's repository and a new pin here.
3. **Sounds and 3D models now exist, and are well credited.** The Little House ships 18 sounds, 30 models and 8
   textures, each credited in its `credits.json` with a license file beside it. No other starter or this repo has a
   sound file.
4. **Every `licenseFile` a `credits.json` names exists** (29 of 29 across starters). Four upstream entries (all
   New York's data sources) name a license but no file.
5. **`Resources/THIRD_PARTY_NOTICES.md` is incomplete.** It omits the qrcode library, WebView2, the Geist font,
   `stb_vorbis`, `dr_wav`, `dr_mp3`, the IEEE registry data, the libraries inside three.js's addons, and says nothing
   about logos being trademarks. [PR #943](https://github.com/lampdotdev/Lamp/pull/943) fixes these.

## The 15 starter repos

`buzzerbeater`, `diskmap`, `fireside`, `homehq`, `hotshelf`, `hours`, `localcrossings`, `newyork`, `sitetoapp`,
`thelittlehouse`, `tidyup`, `today`, `transcriber`, `universalremote`, `weddingwords`, at the commits in each
`starter.md`. Swift sources are Lamp's own and not audited here.

### What every starter has

| Files | Origin | Verdict |
| --- | --- | --- |
| `LICENSE` (MIT, Roo Code, Inc.) | Written for the starter repos. | **Fine** |
| `.github/icon/*`, `icon.png`: 15 icons, each `icon.png`, `AppIcon-square.png`, `.icns`, `Assets.car`, `art.json`, SVG layers | Drawn by Lamp's icon pipeline: a model writes two to four vector shapes (a folder, a check mark) that Icon Composer renders (commit "Icons in Liquid Glass layers, games painted, and the starters redrawn"). Own work, model-written vectors; not pictures from an image model. | **Fine** |
| `.github/preview.png`, `showcase/{poster.png,loop.webp,reel.mp4}`: about 60 files | Screenshots and recorded reels of the starter running. The reels' audio tracks were not examined. | **Fine** |
| `credits.json` | Holds `remixOf`; has an `upstream` list only where noted below. | see below |

### Pictures made with AI, not marked

| Starter | Files | Evidence | Verdict |
| --- | --- | --- | --- |
| `fireside` | `Assets/*.png` (9) | "nine painted pictures" (`APP.md`, the commit adding them); glossy single objects, cut out. | **Notice** |
| `hotshelf` | `Assets/{bottle,dasher,jar,squeeze}.png` (4) | "the four painted bottle styles" (`APP.md`). | **Notice** |
| `sitetoapp` | `Assets/hero.png` (1) | "a glass picture of a browser window turning into an app icon". | **Notice** |
| `newyork` | `icon-art.png`, `.github/icon/art.png`, `.github/icon/AppIcon.icon/Assets/foreground.png` (3) | A game's icon is "a painting" by an image model (`docs/development/desk.md`). A glowing crystal flame in a gold torch. | **Notice** |

PNG metadata says nothing about origin: only an sRGB tag and dimensions. These are "very likely" generated from how
they look and from the docs; the repo has no record of the tool.

### Hot Shelf bottle photos (27 files). **Notice**

`Assets/Bottles/*.png` (26) and `credits.txt`: real product photos from Open Food Facts, "CC BY-SA 3.0", cut out from
the originals; each line of `credits.txt` links the product page and the source image. The About box credits them.
Problems:

- The starter's `credits.json` has an empty `upstream`, its README has no credit, and there is no CC BY-SA license
  text, so Lamp's desk panel, a share and the README show nothing.
- CC BY-SA is share-alike; the cut-outs are adaptations, "shared under the same license", inside a repo licensed MIT.
- The photos show brand names and label art. Those are the makers' trademarks and artwork; the photographer's license
  does not cover them.
- Credit is to "Open Food Facts contributors" as a group; the image URL leads to each contributor.

### New York (`newyork`)

| Path | Files | Origin and license | Verdict |
| --- | ---: | --- | --- |
| `Web/` html, css and js | about 36 | Slop New York (`credits.json`, MIT, at its pinned commit), `Web/LICENSE-slop-newyork` present. | **Fine** |
| `Web/three/` | all addons | three.js with `LICENSE` and `NOTICE.md` beside it. | **Fine** |
| `Assets/Tools/build-elevation.mjs` | 1 | Written for this starter. | **Fine** |
| `Web/data/elevation.bin.gz` | 1 | Open Terrain Tiles on AWS (bare earth from USGS 3DEP), per the tool's header. | **Notice** |
| `Web/js/building-geodata.bin.gz`, `tree-geodata.bin.gz` | 2 | Derived map data; `credits.json` names NYC Open Data, OpenStreetMap and MTA data as the sources. | **Notice** |
| `Web/js/nyc-geodata.js` | 1 | Header: NYC Open Data and OpenStreetMap (ODbL), 1.1 MB. | **Notice** |

`credits.json` has five upstream entries: Slop New York (license file present), OpenStreetMap map data (ODbL-1.0),
NYC Open Data (`LicenseRef-NYC-Open-Data`), Terrain Tiles (`LicenseRef-USGS-Public-Domain`) and MTA Subway Entrances
and Exits (`LicenseRef-NY-Open-Data`). The last four name a license but no file, and the three `LicenseRef-` terms have
no text in the repo. The README does say "Map data is ODbL-1.0: it stays under that licence, credited, in this remix."
ODbL asks for attribution and for a derived database to be offered under ODbL; whether that fits an MIT repo is
decision 4.

### Home HQ (`homehq`). **Fine**

photo-frame-dashboard (MIT, `Web/LICENSE-photo-frame-dashboard`), Archivo and Instrument Serif (OFL-1.1, license text
in `Web/fonts/OFL-*.txt`, three woff2 files). All three `licenseFile`s exist. `js/icons.js` is a small stroke icon set
with no source given; it came with the upstream project.

### The Little House (`thelittlehouse`). **Fine**

The model for how credit should look. 30 glTF models, 18 mp3 sounds, 8 textures, a moodist-derived sound mixer and
three.js, with 25 upstream entries each carrying a license file:

- moodist (MIT) and three.js (MIT) with their licenses; 18 sounds from Freesound, CC0, each credited by title and link
  (`Licenses/sounds/LICENSE-CC0-1.0.txt`, `NOTICE-sounds.md`).
- Kenney's Furniture Kit, Nature Kit and Particle Pack (CC0, one license file each) for the models and textures.
- Two Poly Pizza models (CC0, `Licenses/models/`).

Not checked: that every one of the 30 models and 8 textures is accounted for by those packs.

### Starters with only Lamp's own code and icon

`buzzerbeater`, `diskmap`, `hours`, `localcrossings`, `tidyup`, `today`, `transcriber`, `universalremote`,
`weddingwords`. No third-party picture, font, sound or library. **Fine.**

## Provider logos and brand marks

Trademarks used nominatively, to say which provider a setting talks to. They are not licensed by MIT: the MIT license
of the icon set they came from covers the set's files, not the marks.

| File | Origin | Verdict |
| --- | --- | --- |
| `Resources/ProviderLogos/{anthropic,openai,openrouter}.png` (128 px, used by `Setup.swift`) | Lobe Icons (`@lobehub/icons-static-png`, MIT), per the commit that added them and `THIRD_PARTY_NOTICES.md`. Not compared with the package here. Eighteen other providers' logos were removed in "Fewer AI providers" and remain in git history. | **Notice** |

The site's copies of these logos were removed. What is missing is a sentence saying the marks belong to their owners
and are used only to identify them. Other brand marks: product and maker names in code and docs (naming, not artwork),
the Hot Shelf labels (above), and the Lamp name and icon, which the README already carves out of MIT. The site's
sharing image is now a composite of Lamp's own starter screenshots, and the earlier AI pictures of an Apple laptop and
watch, a kart game and an invaders game were removed (see "Removed since the first audit").

## Libraries shipped as files

### `Resources/WebLibraries/` (327 files). **Fine**

| Folder | Files | What | License file | Notice |
| --- | ---: | --- | --- | --- |
| `three/` | 318 | three.js (r187dev, a pinned commit): the build files and a set of `examples/jsm` as `addons/` | `LICENSE` (MIT) | `NOTICE.md` |
| `phaser/` | 3 | Phaser 3.90.0, checked against the npm SHA-512 | `LICENSE.md` (MIT) | `NOTICE.md` |
| `rapier/` | 3 | Rapier 0.21.0 (wasm inside the JS), checked against the npm SHA-512 | `LICENSE` (Apache-2.0) | `NOTICE.md` |
| `qrcode/` | 3 | qrcode-generator 2.0.4, checked against the npm SHA-512 (`scripts/update-qrcode.sh`) | `LICENSE` (MIT) | `NOTICE.md` |

Under `three/addons/libs/` sit six libraries by other authors: fflate, lil-gui, meshoptimizer's decoder, potpack,
stats.js and tween.js (all MIT or ISC, licensed in their file headers; the folder's `LICENSE` is three.js's alone).
`loaders/EXRLoader.js` carries the BSD-style notices of the code it ports. None blocks release.
`THIRD_PARTY_NOTICES.md` lists three.js, Phaser and Rapier but not qrcode.

### `Resources/GameKit/` (32 files). NOTICE checked against what is there

`NOTICE.md` lists sokol (five headers), HandmadeMath, cgltf, stb (`stb_image`, `stb_vorbis`) and dr_libs (`dr_wav`,
`dr_mp3`). `libraries/` holds exactly those 12 files: nothing is there that the NOTICE does not name and nothing it
names is missing. Versions and licenses match the file headers (sokol zlib, cgltf 1.15 MIT, stb public domain or MIT,
dr_libs public domain or MIT-0), each license text is in the NOTICE or at the end of the file. One wording
difference: the NOTICE calls HandmadeMath "public domain (CC0 1.0)"; its header says only "in the public domain", with
a fallback grant. The other 20 files are Lamp's own code, scaffolds and web glue. **Fine.**
`THIRD_PARTY_NOTICES.md` lists sokol, HandmadeMath, cgltf and `stb_image` but not `stb_vorbis`, `dr_wav` or `dr_mp3`
(3 files, **Notice**; they impose no duty to credit, so this is accuracy).

### `Resources/LGPhones/` (17 files). **Fine**

`ws` (MIT) with its `LICENSE` at `node_modules/ws/LICENSE`, listed in `THIRD_PARTY_NOTICES.md`; `relay.js` and
`service.js` are Lamp's own.

## `Resources/Devices/` (2 files). **Fine**

`roku.json`, `xbox-one.json`: device integrations as data, with Lamp's own small template apps and setup steps and a
`sources` list of documentation pages. No copied artwork, data or sample code.

## `Resources/asset-catalog.json` (1 file). **Fine**

An index of 37 free asset packs (932 entries), mostly models from Poly Pizza and OpenGameArt, written by
`scripts/update-assets.py`. Lamp ships the index only; the files are fetched into an app when the agent chooses one and
are pinned by SHA-256. Only CC0 and CC-BY are listed, and CC-BY credit is recorded in the app's `credits.json`.

## Other bundled binaries and data in `Resources/`

| Path | Files | Origin as far as the repo shows | Verdict |
| --- | ---: | --- | --- |
| `WebHost/App.exe`, `Microsoft.Web.WebView2.Core.dll` | 2 | The Xbox web host, built from `lamp_web_host.cpp` and `lamp_controllers.h` by `scripts/build-web-host.sh` (WebView2, the Windows SDK contracts and C++/WinRT pinned by version, checksum or commit). The DLL is Microsoft's redistributable library; the exe is built against it with Microsoft's SDK headers. | **Notice** |
| `WebHost/WebView2-LICENSE.txt`, `lamp_web_host.cpp`, `lamp_controllers.h` | 3 | Microsoft's BSD-3-Clause text for WebView2; Lamp's own source. | **Fine** |
| `vendors.xz` | 1 | The IEEE's public MA-L/MA-M/MA-S registry, trimmed by `scripts/update-vendors.sh` (53,647 lines). No statement of its terms or a credit in the repo. | **Notice** |
| `TVCertificates/vd_tizen_dev_author_ca.der`, `vd_tizen_dev_public2.der` | 2 | Samsung's public Tizen developer CA certificates (valid to 2040 and 2029). The commit that added them ("TV apps for Samsung and LG TVs", #542) does not say where they came from. Public certificates, not keys. | **Unknown** (low risk) |
| `Icon/AppIcon.icon/*` (3: `icon.json`, `sheet.png`, `stripes.png`), `AppIcon.icns`, `AppIcon.png`, `Assets.car` | 6 | Lamp's own icon (the stripes mark), rendered at each size. The name and icon are outside MIT per the README. | **Fine** |
| `DMG/sky.png`, `DMG/background.tiff` | 2 | A night sky over dunes with stars (commit "DMG: show Lamp, an arrow and Applications over a night sky"). No record of how `sky.png` was made; it looks generated. `background.tiff` is drawn from it by `scripts/dmg-background.swift`. | **Unknown** |

`Resources/skills/` and `Resources/lamp-tools.*` are Lamp's own prompts and tools. `experiments/browser-connector/
extension/icons/` (8 PNGs) are Lamp's own icons. Not counted. The test fixtures that look like captured device data
(`Tests/Fixtures`, `Tests/PhoneInstall/Fixtures`) use placeholder identifiers and addresses.

## The site (`site/`)

| Path | Files | Origin | Verdict |
| --- | ---: | --- | --- |
| `lib/fonts/Geist-*.ttf`, `OFL.txt` | 3 | Geist, OFL-1.1, "Copyright (c) 2023 Vercel, in collaboration with basement.studio"; license text beside it. Used to draw share cards. No other web fonts or icon packages. | **Fine** |
| `public/favicon.png`, `apple-touch-icon.png`, `og.jpg` | 3 | Lamp's own icon; the sharing image is a composite of Lamp's own starter screenshots (commit "Replace the site's sharing image with a shelf of sleeves"). | **Fine** |
| `src/assets/AppIcon.png` | 1 | Lamp's icon. | **Fine** |
| `src/assets/starters/*.png` | 15 | One picture per starter, added with the remix homepage (#818) and "Add The Little House as a Lamp starter". Screenshots of the starters. | **Fine** |
| `src/assets/ideas/icons/` | 80 | One icon per idea, drawn by an image model through Codex signed in with ChatGPT from a line in `site/scripts/idea-art/briefs.txt`, put on Lamp's tile by `tile.swift` (`idea-art/README.md`, commit "Give every idea an icon and a picture of it in use"). | **Notice** |
| `src/assets/ideas/thumbs/` | 80 | One picture of each idea in use; same process (`prompts.py`, `draw.sh`). | **Notice** |
| `src/assets/ideas/objects/` | 9 | One object per category; same process, from `categories.txt`. | **Notice** |

The site's other pictures from the first audit (examples, places, dragons, story, the receipt, the app icon row, the
provider logos, a Lamp Dev screenshot) are no longer in the tree. The ideas pictures are the only AI pictures left on
the site, and the site says "Made with AI inside" about what Lamp's apps do, not about its own pictures. Only a sample
of the 169 was viewed; they are product-shot style Mac windows, phones and games with invented content, and the
earlier set had shown Apple hardware and a game resembling a known franchise, so the rest are worth a look.

## AI-made pictures

**Marked in a `credits.json` `generated` list: none**, in this repo or any of the 15 starters. Looks generated and is
not marked:

| Pictures | Count | How sure |
| --- | ---: | --- |
| `site/src/assets/ideas/*` | 169 | Certain: the repo has the briefs, prompts and scripts. |
| Fireside, Hot Shelf (painted styles) and Site-to-App pictures | 14 | Very likely: "painted pictures" by `make_art`. |
| New York icon art (3 files) | 3 | Very likely: a game's icon is painted by an image model. |
| `Resources/DMG/sky.png` | 1 | Likely from how it looks; no record. |

Not generated, checked by eye or by record: starter previews and reels (screenshots and recordings), the Hot Shelf
bottle cut-outs (photographs), the site's starter screenshots, Lamp's own icon.

## Removed since the first audit

Taken out of the tree by `main`: the site's examples, places, dragons, story, receipt, app-icon row, logos copies and
Lamp Dev screenshot, the onboarding film and its stills, the Lamp icon's earlier SVG layers, and every starter's
source, icons and assets (now in the starter repos). They remain in git history, which will be published with the
repo; the history includes the AI pictures of Apple hardware and the kart game, and the Hot Shelf photos with their
earlier credits.

## Decisions for the team, highest risk first

1. **Hot Shelf bottle photos (27 files, in a public repo already).** CC BY-SA 3.0 share-alike photos of branded
   packaging inside an MIT repo, with no license text and no `credits.json` entry. Choose: keep them with a
   `credits.json` entry, the CC BY-SA text beside them and a line that this folder is not MIT; or remove them (a
   bottle without a photo already gets its label looked up or a painted placeholder). Either way, decide whether
   showing makers' packaging is acceptable.
2. **Git history carries what was removed.** The history that will be published has the pictures that were taken out,
   including AI images of Apple products and a game resembling a known franchise. Decide whether to publish history
   as is, or squash or rewrite before opening up.
3. **A policy for AI-made pictures.** Decide how they are disclosed (a `generated` list in each starter's
   `credits.json`; a note for the site's ideas pictures), whether the repo should claim MIT over them (copyright in
   such images is unsettled and the image tools' terms for commercial reuse were not checked), and whether
   model-written icon vectors count.
4. **New York's map and terrain data.** OpenStreetMap is ODbL (attribution and share-alike on a derived database),
   NYC Open Data, Terrain Tiles and the MTA data have their own terms, and none has a license file. Add a NOTICE with
   the terms and links in the starter repo; decide whether the data fits an MIT repo or is labeled as an exception.
5. **Unknown origin (4 files).** `Resources/DMG/sky.png` and the DMG background built from it, and the two Samsung CA
   certificates. Record the tool or replace the sky; record where the certificates were taken from.
6. **Complete `THIRD_PARTY_NOTICES.md` and add the trademark sentence.** Done in PR #943; no decision needed.
7. **The starters' own licenses.** Every starter repo says MIT, Roo Code, Inc. over its whole tree. Decide whether
   each repo's README and `LICENSE` should say that bundled third-party work keeps its own license (the New York,
   Home HQ and The Little House repos already carry theirs beside the files).
