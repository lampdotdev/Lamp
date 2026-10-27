# Asset audit before open-sourcing

A check of every picture, font, sound, data file, library and binary the repository would publish: where it came from,
what license it carries, and what is still missing. Taken from the repo as of this branch (base `main` at the commit
named in the PR). Nothing was changed except this file. Only what the repo shows is used: `credits.json`, `APP.md`,
`about.json`, NOTICE and LICENSE files beside the files, the git history (the commit that added each group and its
message), the code comments that say how a picture was made, and file metadata. No source was contacted, so a license
a file states is taken as stated, not checked at its source.

Verdicts, used in every table:

- **Fine**: origin is clear and any license that applies is in place, or it is Lamp's own work.
- **Notice**: origin is clear, but a license file, credit or marking is missing or incomplete.
- **Unknown**: the repo does not say where it came from; the team decides.

## Counts

Files counted are pictures, icons, fonts, data, libraries and binaries in the places listed below, 859 in all. Swift and
other source, `APP.md`, `about.json`, `icon.json`, `starter.md`, `capabilities.json` and `Tests/` are not counted.

| Verdict | Files |
| --- | ---: |
| Fine | 585 |
| Notice | 268 |
| Unknown | 6 |

Of the 268 needing a notice, 205 are AI-made pictures on the site and 22 are AI-made pictures or icon art in starters (14 pictures, 8 New York icon files),
none marked as made with AI (see "AI-made pictures"). The rest are the Hot Shelf photos (27), New York's map data
(2), provider logos (6), the Xbox web host binaries (2), the IEEE-derived list (1) and three game-kit libraries
missing from the top-level notices (3).

## Findings that cut across everything

1. **No picture is marked as made with AI.** Only two starters have a `credits.json` (New York, Home HQ), and neither
   has a `generated` list. No other file in the repo marks a picture as generated. Yet about 225 pictures were made
   with image models (list below), and the repo itself says so in code comments, commit messages and
   `site/scripts/idea-art/README.md`.
2. **No sound files at all.** There is no `.wav`, `.mp3`, `.m4a`, `.caf` or similar tracked anywhere. The New York
   starter's audio is synthesized in code (`audio-synthesis.js`). The only video is the onboarding film.
3. **Every license a `credits.json` names with a `licenseFile` has that file** (4 of 4, see below). Three of the seven
   upstream entries name a license but no file.
4. **`Resources/THIRD_PARTY_NOTICES.md` is incomplete.** It omits the WebView2 library, the Geist font, the two fonts in
   Home HQ, `stb_vorbis`, `dr_wav`, `dr_mp3`, the IEEE registry data and the libraries inside three.js's addons. The
   licenses for those exist in other places, just not in the one file the README points people to.
5. **Several AI pictures show other people's products or characters** (an Apple laptop, watch and wallpaper, a kart-racing
   game that closely echoes a well-known franchise, an invaders-style shooter). See decision 2.

## Starters (`Resources/Starters/*`)

Fourteen starters. `Sources/` is Lamp's own Swift code and is not part of this audit.

### Starter icons: 139 files across 14 starters

- Thirteen starters have a "glass" icon: `icon.png`, `AppIcon-square.png`, `AppIcon.icns`, `Assets.car`, `art.json`,
  `icon.json` and an `AppIcon.icon/` folder of SVG layers (131 files). `art.json` holds the layers as SVG written by a
  model through Lamp's icon pipeline (`GlassIcons`); the layers are simple geometry (a folder, a check mark). Added
  with the starters in the commit "Icons in Liquid Glass layers, games painted, and the starters redrawn" and
  "Starters ship their icons". Own work, AI-assisted. **Fine.** The SVG layers are not pictures made by an image model,
  so they are not what `generated` is for; the team may still want to say so (decision 3).
- New York's icon (8 files: `art.png`, `AppIcon.icon/Assets/foreground.png`, and the files drawn from them) is a
  painting by an image model of a glass flame in a gold torch (the commit message says games get "one rich, glossy 3D
  painting"; `docs/development/desk.md` says a game's icon is "a painting (icon/art.png)"). Not marked. **Notice**: mark
  `icon/art.png` and `icon/AppIcon.icon/Assets/foreground.png` as generated.

### Previews: 14 files (`*/preview.png`)

Screenshots of each starter's own window, added with the starters. The Hot Shelf and New York previews show the
bottle photos and the Slop New York scene respectively, so they inherit those notices. **Fine.**

### Pictures in `Assets/`

| Where | Files | Origin as far as the repo shows | Verdict |
| --- | ---: | --- | --- |
| `fireside/Assets/*.png` | 9 | "nine painted pictures" (commit "Starters: add Fireside, drop Countdowns", `APP.md`). Painted by Lamp's `make_art` (an image model) in the style of the icon. They look generated: soft 3D gloss, one object, cut out. No credits.json. | **Notice**: mark as generated |
| `hotshelf/Assets/{bottle,dasher,jar,squeeze}.png` | 4 | "the four painted bottle styles" (`APP.md`). Look generated (the jar has the usual glossy-render artifacts). Unmarked. | **Notice**: mark as generated |
| `sitetoapp/Assets/hero.png` | 1 | A "glass picture of a browser window turning into an app icon" (`APP.md`). Looks generated. Unmarked. | **Notice**: mark as generated |
| `hotshelf/Assets/Bottles/*.png` | 26 | Real product photos from Open Food Facts, "CC BY-SA 3.0", "cut out from the originals" (`Bottles/credits.txt`, commit "Hot Shelf: a lit studio shelf of real bottles"). Each line of `credits.txt` links the product page and the source image. The About box credits them. | **Notice** (below) |
| `hotshelf/Assets/Bottles/credits.txt` | 1 | The credit for the 26 photos. | Counted with the row above |

EXIF and PNG metadata tell nothing about origin for any of these: the Fireside, Hot Shelf painted and Site-to-App
pictures carry only an sRGB tag and a dimension-only EXIF block (what CoreGraphics writes); the bottle cut-outs
carry XMP written by the cut-out tool.

**Hot Shelf bottle photos.** Four problems, none fixed by what is in the repo today:

- `credits.txt` states the license but there is no license text and no `credits.json` for the starter, so the desk's
  info panel and a shared copy cannot show the credit (only the About box in the Swift source does).
- CC BY-SA is share-alike. The cut-outs are adaptations of the photos and "shared under the same license", which
  conflicts with the repository's blanket MIT unless the folder is labelled as an exception.
- The photos show packaging: brand names, labels and logos of the sauces' makers. Those are the makers'
  trademarks and label art; CC BY-SA from the photographer does not license them.
- Credit is to "Open Food Facts contributors" as a group; the individual contributor of each image is not recorded
  (the source image URL is, which leads to it).

### New York (`newyork/`)

| Path | Files | Origin and license | Verdict |
| --- | ---: | --- | --- |
| `Web/index.html`, `Web/css/style.css`, `Web/js/*.js` except the geodata | 35 | Slop New York at commit `199f010c…` (`credits.json`), MIT, `Web/LICENSE-slop-newyork` is present and its text matches. The git history shows it taken from the Xbox app and updated ("New York: no keyboard beep, and the latest Slop New York (#658)"). | **Fine** |
| `Web/LICENSE-slop-newyork` | 1 | The upstream license. | **Fine** |
| `Assets/Tools/build-elevation.mjs` | 1 | Written for this starter; fetches the elevation tiles. | **Fine** |
| `Web/js/nyc-geodata.js` | 1 | Header: generated from NYC Open Data (borough boundaries, street centerlines, parks) and OpenStreetMap (Central Park features, piers, landmark footprints, the New Jersey shore), "© OpenStreetMap contributors (ODbL)". 1.1 MB of polygons. | **Notice** |
| `Web/data/elevation.bin.gz` | 1 | Built by `build-elevation.mjs` from the open Terrain Tiles on AWS (Mapzen terrarium encoding; bare earth from USGS 3DEP). Commit "New York: real ground heights (#667)". | **Notice** |
| icon files | 8 | See "Starter icons". | **Notice** |

`credits.json` lists four sources. The license file for the first is where `licenseFile` says. The other three
(OpenStreetMap, ODbL-1.0; NYC Open Data, `LicenseRef-NYC-Open-Data`; Terrain Tiles, `LicenseRef-USGS-Public-Domain`)
name a license but no file. For the two with `LicenseRef-` terms there is no text in the repo to point at. ODbL asks
for attribution and for a derived database to be offered under ODbL; the geodata file is a derived database. How that
fits an MIT repo is decision 5.

### Home HQ (`homehq/`)

| Path | Files | Origin and license | Verdict |
| --- | ---: | --- | --- |
| `Web/` html, css, js (25) | 25 | photo-frame-dashboard at commit `0bff55ef…` (`credits.json`), MIT, `Web/LICENSE-photo-frame-dashboard` present. `js/icons.js` is a small stroke icon set in the style of common open icon sets; the header says "minimal stroke icon set" and gives no source, so it is taken to come with the upstream project. | **Fine** |
| `Web/fonts/archivo.woff2`, `OFL-archivo.txt` | 2 | Archivo, OFL-1.1, license text present and its copyright line names the project's authors; `credits.json` names it. | **Fine** |
| `Web/fonts/instrument-serif*.woff2` (2), `OFL-instrument-serif.txt` | 3 | Instrument Serif, OFL-1.1, same. | **Fine** |

`credits.json` has three entries, all with a `licenseFile` that exists. Two checks the OFL needs, passed: each font's
license is shipped beside it, and the fonts are not sold on their own.

### Starters with nothing but Lamp's own code and icon

Buzzer Beater, Disk Map, Hours, Local Crossings, Tidy Up, Today, Transcriber, Universal Remote, Wedding Words: an
icon and a preview (counted above), Swift sources, `APP.md`. Today also has a `Widget/` and Fireside a `Share/`
folder of Swift. No third-party picture, font, sound or library. **Fine.**

## Provider logos and brand marks

These are trademarks used nominatively, to say which provider a setting talks to. They are not licensed by MIT:
the MIT license of the icon set they came from covers the set's files, not the marks. Two copies exist, byte
identical:

| File | Where | Origin | Verdict |
| --- | --- | --- | --- |
| `anthropic.png`, `openai.png`, `openrouter.png` (128 px) | `Resources/ProviderLogos/` (used by `Setup.swift`) | Lobe Icons, `@lobehub/icons-static-png`, MIT (commit "Reorganize Settings into Building, Apps and Providers": "their logos (Lobe Icons, MIT)"; `THIRD_PARTY_NOTICES.md`). Eighteen other providers' logos were dropped in "Fewer AI providers" and remain in git history. The files were not compared with the package here. | **Notice** |
| the same three | `site/src/assets/logos/` | Copies of the above (added in "A one-page website for lamp.dev"). | **Notice** |

What is missing is a sentence saying the marks belong to their owners and are used only to identify them; the
license for the set is already in `THIRD_PARTY_NOTICES.md`. Other brand marks in the repo:

- Starter `APP.md` and Swift sources name makers and products (the Hot Shelf sauces, Open Food Facts, device makers).
  That is naming, not artwork.
- The Hot Shelf bottle photos carry makers' labels (above).
- AI pictures on the site show an Apple laptop, an Apple watch and a macOS wallpaper (below).
- The Lamp name and icon are already carved out of MIT in the README.

## Libraries shipped as files

### `Resources/WebLibraries/` (324 files). **Fine**

| Folder | Files | What | License file | Notice |
| --- | ---: | --- | --- | --- |
| `three/` | 318 | three.js at commit `fae87345…` (r187dev): the four build files and a set of `examples/jsm` as `addons/` | `LICENSE` (MIT) | `NOTICE.md` says commit and how each file was checked |
| `phaser/` | 3 | Phaser 3.90.0 `phaser.esm.min.js`, checked against the npm registry's SHA-512 | `LICENSE.md` (MIT) | `NOTICE.md` |
| `rapier/` | 3 | Rapier 0.21.0 (`@dimforge/rapier3d-compat`, wasm inside the JS), checked against the npm SHA-512 | `LICENSE` (Apache-2.0) | `NOTICE.md` |

Each folder holds a license beside the library and a NOTICE saying what it is. `THIRD_PARTY_NOTICES.md` lists all
three. Small things, none blocking:

- Under `three/addons/libs/` sit six libraries by other authors: fflate (MIT), lil-gui (MIT), meshoptimizer's decoder
  (MIT, with a header naming its author), potpack (ISC), stats.js (MIT) and tween.js (MIT). Their licenses are in the
  file headers where they exist, and the folder's `LICENSE` is three.js's alone.
- `three/addons/loaders/EXRLoader.js` carries the BSD-style notices of the code it ports, in its header.
- The `SMAA*` addons embed two base64 lookup textures from the same upstream; they ship under three.js's license.
- The Rapier wasm is Apache-2.0 and the package has no NOTICE file of its own, so Apache's NOTICE rule is met by the
  LICENSE alone.

### `Resources/GameKit/` (29 files). NOTICE checked against what is there

`NOTICE.md` lists sokol (five headers), HandmadeMath, cgltf, stb (`stb_image`, `stb_vorbis`) and dr_libs (`dr_wav`,
`dr_mp3`). The directory `libraries/` holds exactly those 12 files; nothing is there that the NOTICE does not name and
nothing the NOTICE names is missing. Versions and licenses match the file headers: sokol zlib (full text in the
NOTICE), cgltf 1.15 MIT (text in NOTICE), HandmadeMath public domain, stb public domain or MIT (text at the end of
each file), dr_libs public domain or MIT-0 (text at the end of each file). One wording difference: NOTICE says
HandmadeMath is "public domain (CC0 1.0)"; the header says "in the public domain" with a fallback grant, no CC0.

The other 17 files are Lamp's own code, scaffolds and the web glue (`lamp-game.js`, `lamp-phaser.js`). **Fine.**

The shortfall is in `THIRD_PARTY_NOTICES.md`, which lists sokol, HandmadeMath, cgltf and stb_image but not
`stb_vorbis`, `dr_wav` or `dr_mp3` (3 files, **Notice**). Their licenses impose no duty to credit (public domain or
MIT-0), so this is accuracy, not a legal gap.

## `Resources/Devices/` (2 files). **Fine**

`roku.json`, `xbox-one.json`: device integrations as data. They hold Lamp's own small template apps (a BrightScript
scene, a web page and stylesheet), the steps for setting each device up and a `sources` list of documentation pages
(Roku and Microsoft developer docs). No copied artwork, data tables or sample code; the template files are a few
hundred characters of original code each.

## Other bundled binaries and data in `Resources/`

| Path | Files | Origin as far as the repo shows | Verdict |
| --- | ---: | --- | --- |
| `WebHost/App.exe`, `Microsoft.Web.WebView2.Core.dll` | 2 | The Xbox web host, built from `lamp_web_host.cpp` by `scripts/build-web-host.sh` (which pins the WebView2 1.0.3719.77, the Windows SDK contracts and C++/WinRT by version, checksum or commit). The DLL is Microsoft's redistributable library; the exe links it and C++/WinRT (MIT). | **Notice** |
| `WebHost/WebView2-LICENSE.txt`, `lamp_web_host.cpp` | 2 | Microsoft's BSD-3-Clause text for WebView2; Lamp's own source. | **Fine** |
| `vendors.xz` | 1 | The IEEE's public MA-L/MA-M/MA-S registry, trimmed by `scripts/update-vendors.sh` into prefix and maker name (53,647 lines). The IEEE publishes the lists freely but the repo carries no statement of its terms or a credit. | **Notice** |
| `TVCertificates/vd_tizen_dev_author_ca.der`, `vd_tizen_dev_public2.der` | 2 | Samsung's public Tizen developer CA certificates (subject: Samsung VD Author CA, VD DEVELOPER Public CA Class; valid to 2040 and 2029). Added in the TV commit "(#542)"; the commit message does not say where they were taken from, but they are public certificates, not keys. | **Unknown** (low risk) |
| `Onboarding/onboarding.mp4`, `step0-2.png` | 4 | Rendered in Blender from Lamp's own model (`design/lamp/README.md`: "rendered offline in Blender Cycles", lamp geometry in `LampModel.swift`, scripts `render-onboarding.py`, `encode-onboarding.py`). | **Fine** |
| `Icon/AppIcon.icon/*` (5), `AppIcon.icns`, `AppIcon.png`, `Assets.car` | 8 | Lamp's own icon: four vector layers, "Give Lamp a light icon: a glass flame over two rings". The name and icon are outside MIT per the README. | **Fine** |
| `DMG/sky.png`, `DMG/background.tiff` | 2 | A night sky over dunes with stars (commit "DMG: show Lamp, an arrow and Applications over a night sky"). No record of how `sky.png` was made; it looks generated, in the style of `site/public/og.jpg`. `background.tiff` is drawn from it by `scripts/dmg-background.swift`. | **Unknown** |

`Resources/skills/` (32 files) and `Resources/lamp-tools.*` are Lamp's own prompts and tools; not part of this
audit beyond a check that none embeds third-party files. `experiments/browser-connector/extension/icons/` (8 PNGs)
are Lamp's own icons at several sizes. **Fine**, not counted above.

## The site (`site/`)

### `site/lib/fonts/` (3 files). **Fine**

`Geist-Regular.ttf`, `Geist-Bold.ttf` and `OFL.txt` (OFL-1.1, "Copyright (c) 2023 Vercel, in collaboration with
basement.studio"). Used only to draw share cards (`lib/wish-card.js`). The license text is present beside the fonts.
No other web fonts, icon fonts or icon packages are loaded (`package.json` and `src` checked). Geist is not in
`THIRD_PARTY_NOTICES.md` (see finding 4).

### `site/public/` (3 files counted)

| File | Origin | Verdict |
| --- | --- | --- |
| `favicon.png`, `apple-touch-icon.png` | Lamp's own icon, rendered at size ("Give Lamp a light icon"). | **Fine** |
| `og.jpg` | The share image: a magic lamp under a large moon over dunes, stars. Commit "Website: a magic lamp under the moon as the share image" (no body). Looks generated; nothing records a tool. The lamp is the classic genie-lamp shape. | **Unknown** |

### `site/src/assets/` (211 files)

| Folder | Files | What | Origin as far as the repo shows | Verdict |
| --- | ---: | --- | --- | --- |
| `ideas/icons/` | 80 | one icon per idea | Drawn by an image model through Codex signed in with ChatGPT, from a line in `site/scripts/idea-art/briefs.txt`, then put on Lamp's own tile by `tile.swift`. Documented in `site/scripts/idea-art/README.md` and commit "Give every idea an icon and a picture of it in use". | **Notice** |
| `ideas/thumbs/` | 80 | one picture of each idea in use | Same (`prompts.py`, `draw.sh`, `run.sh`, `finish.sh`). | **Notice** |
| `ideas/objects/` | 9 | one object per category | Same, from `categories.txt`. | **Notice** |
| `examples/` | 5 | examples on a Mac, TV, watch, phone, Xbox | "pictures drawn the way the ideas page's are" (commit "Homepage: examples on more devices…"). | **Notice** |
| `places/` | 4 | desk, living room, pocket, wrist | "draw the places as the ideas' pictures are" (commit). | **Notice** |
| `dragons/` | 3 | one dragon as etching, clay, comic | `AICards.astro`: "Drawn by an image model, as the ideas page's pictures are." | **Notice** |
| `story/` | 7 | seven dinner photos for the recipes story | `ChangeStory.astro`: "the photos are drawn by an image model". | **Notice** |
| `icons/` | 17 | a row of app icons | "a row of icons Lamp made" (commit "Website: an icon shelf…"); made by Lamp's icon pipeline, which paints with an image model. | **Notice** |
| `receipt.png` | 1 | a receipt icon "in the manner of the Mac's from around 2008" | Commit "Homepage: a short pricing section, with a receipt for nothing". No record of how it was made; looks generated. | **Unknown** |
| `apps/habit-streaks.png` | 1 | a window of an app Lamp built | "Four real windows from Lamp Dev" (commit "Website: a carousel of apps Lamp built"): a screenshot of Lamp's own output. | **Fine** |
| `AppIcon.png` | 1 | Lamp's icon | Own. | **Fine** |
| `logos/*.png` | 3 | provider logos | See "Provider logos and brand marks". | **Notice** |

The 205 AI-made pictures (the first eight rows) are described as such only in source comments and a developer README.
The site says "Made with AI inside" about what Lamp's apps do, not about its own pictures. The logos are counted with
the provider logos.

## AI-made pictures

**Marked in `credits.json`'s `generated` list: none.** There are only two `credits.json` files in the repo and neither
has the list. Pictures that look generated and are not marked, with how sure that is:

| Pictures | Count | How sure |
| --- | ---: | --- |
| `site/src/assets/ideas/*` | 169 | Certain: the repo has the briefs, prompts and scripts. |
| `site/src/assets/{examples,places,dragons,story}/*` | 19 | Certain: commit messages and code comments say an image model drew them. |
| `site/src/assets/icons/*` | 17 | Very likely: made by Lamp's own icon pipeline. |
| `fireside/Assets/*`, `hotshelf/Assets/{bottle,dasher,jar,squeeze}.png`, `sitetoapp/Assets/hero.png` | 14 | Very likely: "painted pictures" by `make_art`; look generated. |
| `newyork/icon/art.png` and `…/AppIcon.icon/Assets/foreground.png` | 2 | Very likely: icon.json's `game` painting path. |
| `site/public/og.jpg`, `site/src/assets/receipt.png`, `Resources/DMG/sky.png` | 3 | Likely from how they look; no record at all. |
| the 13 starter glass icons' SVG layers | 40 | Model-written vector shapes; not an image model. |

Not generated, checked by eye: `apps/habit-streaks.png` (a real window screenshot), the onboarding renders (Blender),
the Hot Shelf bottle cut-outs (photographs) and the starter previews (window screenshots).

## Decisions for the team, highest risk first

1. **Hot Shelf bottle photos (27 files).** CC BY-SA 3.0 share-alike photos of branded packaging, in an MIT
   repository, with no license text and no `credits.json`. Choose one: keep them, with a `credits.json` entry, the
   CC BY-SA text beside them and a README line that this folder is not MIT; or remove them (a bottle without a photo
   already gets its label looked up or a painted placeholder, per `APP.md`). Either way, decide whether
   showing makers' packaging is acceptable.
2. **AI pictures that echo other people's products and characters.** The kart-racing example
   (`site/src/assets/examples/street-racer.jpg`) closely resembles a well-known franchise's racing game (a capped
   driver in a kart, "1st", coins, a track map with character heads); `places/desk.jpg` and `places/wrist.jpg` show an
   Apple laptop and watch, a macOS wallpaper and Memoji-like faces; `ideas/thumbs/inbox-invaders.jpg` is an
   invaders-style shooter. Decide whether to regenerate, blur or drop these before the repo and site are public, and
   whether to review the other 160 thumbnails the same way (only a sample was viewed).
3. **A policy for AI-made pictures.** Decide how they are disclosed (mark starters' pictures in a `credits.json`
   `generated` list; add a short note for the site's pictures), and whether the repo should claim MIT over them
   (the law on copyright in such images is unsettled, and the image tools' terms for commercial reuse were not
   checked). Also decide whether model-written SVG icon layers count.
4. **Unknown origin (6 files).** `site/public/og.jpg`, `site/src/assets/receipt.png`, `Resources/DMG/sky.png` and
   the DMG background built from it, and the two Samsung CA certificates. For the first four, record the tool or
   replace them; for the certificates, record where they were taken from (they are public).
5. **New York's map and terrain data.** OpenStreetMap is ODbL (attribution and share-alike on a derived database), NYC
   Open Data and Terrain Tiles have their own terms, and none has a license file. Add a `NOTICE` with the terms and
   links; decide if shipping `nyc-geodata.js` as part of an MIT repo is acceptable under ODbL or the data should be
   labelled as an exception.
6. **Trademarks.** Add one paragraph to `THIRD_PARTY_NOTICES.md` or the README: provider logos and other marks belong
   to their owners and are used only to say which provider is meant, outside the MIT license. Applies to
   `Resources/ProviderLogos`, `site/src/assets/logos` and the sauce labels.
7. **Complete `THIRD_PARTY_NOTICES.md`.** Add the WebView2 library (BSD-3, its text is in
   `Resources/WebHost/WebView2-LICENSE.txt`) and C++/WinRT, Geist, Archivo and Instrument Serif (OFL), `stb_vorbis`,
   `dr_wav`, `dr_mp3`, the IEEE registry data behind `vendors.xz`, and the libraries inside three.js's addons.
8. **Make `credits.json` consistent.** Give the New York starter's three data sources license files, give Hot Shelf a
   `credits.json`, and mark `generated` pictures. The `credits.json` format already supports all of it.
