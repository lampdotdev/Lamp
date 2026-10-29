---
name: assets
description: Ready-made models, sprites, tilesets, UI, icons and textures from Lamp's free index (the `assets` tool) - when to use them rather than making things in code or with make_art, keeping one style, loading them so a change shows in the running game, glTF scale, orientation, copies and animations in three.js, sprite sheets and tilesets in Phaser, pictures for apps, and their credit. Read before choosing how a game's or app's things will look.
---

# Ready-made assets

The `assets` tool searches Lamp's index of free work by people who publish it for anyone to use: low-poly 3D packs
(Kenney's city, houses, furniture and survival kits, Quaternius's cars, nature, animals, people and monsters, KayKit's
city bits, a few single models such as a taxi or a bus), Kenney's 2D packs (a platformer, a space shooter, a top-down
racer, pixel-art towns and dungeons, cartoon characters, animals), UI pieces, icons, and ambientCG's tileable
materials. Each is CC0, or CC-BY, which asks for credit. Lamp fetches what you choose into the app, checks it, makes
its pictures smaller where the slowest place it's shown needs that, and writes its credit in credits.json. Nothing is
loaded from the network while the app runs.

## Ready-made or made yourself

Ready-made, when the person wants things that look like real things and there are many of them, or that move in
ways code can't easily give: a city of different buildings, real-looking cars, people and animals that walk and run
(their skeletons and animations come with them, which code can't make), a forest of varied trees, a platformer's
character with its run and jump frames, a tileset for a whole level, a UI that looks finished. And whenever the person
asks for "the same game with different models" or another look for a game that exists (below).

Made yourself, when the thing is simple or abstract (blocks, balls, a neon track), when the game moves its parts itself
(a robot whose arms the player aims, a car whose doors open), when it must match something the person described or
gave, when only one or two things are needed and code makes them well, or when nothing in the index fits the style.
Three.js shapes or Phaser graphics for shapes; `make_art` for a picture in the app's own style (a hero, a boss, a
backdrop, an illustration in an app). The two mix well when the code-made things take the pack's palette.

Look first with `find` (and `kind`), `show: true` to see the candidates together, before deciding: it costs nothing.

## One style

Things seen together come from one pack, or from one author's packs, whose `style` matches: Kenney with Kenney,
Quaternius with Quaternius. Different authors' low-poly flat-color work can sit together, but look at them side by side
(`show`) first: a pastel KayKit house beside a sharp Google Poly taxi reads as two games. Fill what the pack lacks in
code, in its colors and proportions, rather than with a third style. In 2D, pixel art at one size (16 px) never mixes
with smooth vector art.

## Bringing them in

1. `assets` with `find` ("taxi", "low-poly tree", "platformer player") and `kind`, and `show: true`. Each line has an
   id, its triangles, its box in its own units, its animations, its size, its pack, author, license and style.
2. `assets` with `fetch` and the ids. They land in Web/assets/<pack>/ for a game or another page, or Assets/<pack>/ for
   a Swift app (app/src/main/assets/<pack>/ for a native Android app, read with `LampAssets`), and the answer gives each
   file's path as the app loads it.
3. Load each through the runtime (below), then `look_at_app`: a model's size and the way it faces are only certain once
   seen.

The answer leaves out what's too heavy for the slowest place the app is shown (an Xbox One, a TV, a cheap Android
phone): what's listed fits one copy. The scene's total is still yours to keep within the device line's budget: twenty
cars of 3,000 triangles are 60,000.

Keep every asset's path in one table at the top of the game (`const MODELS = { taxi: 'assets/poly-quaternius/car.glb', … }`),
with each thing's real size beside it. Changing the look is then that table, which is also how "the same game with
different models" is made: find a set in another style, fetch it, and point the table at it; the game's code stays.

## In a three.js game

Load with lamp-game.js, never a loader of your own, so a new copy of a file goes into the running game:
`const taxi = await model(MODELS.taxi)` in `init` gives a `THREE.Group` holding the file's scene, with
`taxi.animations`. Pictures: `texture(path, t => { t.colorSpace = THREE.SRGBColorSpace; })`.

- **Scale.** Units differ by author: Kenney's are tiles (a building about 1 unit wide), Quaternius's and KayKit's are
  near meters, Google Poly's are often centimeters (a taxi 90 units long). Scale each to its real size from its box,
  once: a car is about 4.5 m long, a person 1.75 m tall, a door 2 m, a street lamp 5 m.

  ```js
  function fitted(group, meters, axis = 'longest') {
      const size = new THREE.Box3().setFromObject(group).getSize(new THREE.Vector3());
      const now = axis === 'height' ? size.y : Math.max(size.x, size.z);
      group.scale.setScalar(meters / now);
      return group;
  }
  ```

- **Standing on the ground.** A model's origin may be at its center or its feet: after scaling, lift it by the box's
  bottom (`group.position.y = -box.min.y`), inside a holder group that the game moves.
- **Facing.** glTF is y up; most models face +z, some -z or +x. Find out by looking, then turn the holder (or the
  group) once: `holder.add(taxi); taxi.rotation.y = Math.PI`. Never change the meshes inside the group: a new copy of
  the file replaces them.
- **Many copies.** The same model many times: `clone()` shares its geometry and materials (cheap in memory, one draw
  per mesh per copy); for a whole street of one building or a forest of one tree, an `InstancedMesh` per mesh of the
  model (walk it with `traverse`, take each mesh's `geometry` and `material` and its matrix within the model) is one
  draw for all of them. A rigged character (one with `SkinnedMesh`es) is copied with `SkeletonUtils.clone` from
  `three/addons/utils/SkeletonUtils.js`; a plain clone shares one skeleton and every copy moves as one. Copies and
  instances are made again in `assetChanged(path)` (the game skill, "Changes while it's played").
- **Animations.** One `THREE.AnimationMixer` per character, its clips found by the end of their names, which carry
  the rig's name ("CharacterArmature|Walk"):

  ```js
  const clip = name => model.animations.find(a => a.name.split('|').pop() === name);
  const mixer = new THREE.AnimationMixer(character);
  const walk = mixer.clipAction(clip('Walk')), run = mixer.clipAction(clip('Run'));
  walk.play();
  // switching: run.reset().play(); walk.crossFadeTo(run, 0.25, false);
  // in frame(f): mixer.update(f.dt);
  ```

  The fetch answer lists each model's animations. Mixers are made again in `assetChanged(path)`.
- **Materials.** Packs come lit for MeshStandardMaterial. Where the device line names a slow place, swap each mesh's
  material for a `MeshLambertMaterial` with the same `color` and `map` as the game starts. Shadows only where the budget
  allows them: `castShadow` on each mesh through `traverse`.
- **Textures** (ambientCG): color in sRGB, the normal and roughness maps as they are, all with
  `wrapS = wrapT = THREE.RepeatWrapping` and `repeat` set so a tile is about its real size (a 1K brick map covers about
  two meters).

## In a Phaser game

Load in a Boot scene's `preload`, by the path the fetch gave:

- **A sprite sheet with an XML atlas** (most of Kenney's 2D packs):
  `this.load.atlasXML('players', 'assets/kenney-platformer/spritesheet_players.png', 'assets/kenney-platformer/spritesheet_players.xml')`.
  Its frames are named as the XML says ("alienBeige_walk1.png"); an animation is
  `this.anims.create({ key: 'walk', frames: this.anims.generateFrameNames('players', { prefix: 'alienBeige_walk', start: 1, end: 2, suffix: '.png' }), frameRate: 8, repeat: -1 })`.
  Read the XML (the fetch put it beside the sheet) for the frame names before writing them.
- **A tilesheet** (the pixel-art packs): `this.load.spritesheet('tiles', path, { frameWidth: 16, frameHeight: 16, spacing: 1 })`
  with the size and spacing the fetch answer gives, and in a tilemap
  `map.addTilesetImage('tiles', 'tiles', 16, 16, 0, 1)` (margin, then spacing). Its tiles are numbered left to right,
  top to bottom, from 0: look at the sheet before writing the level's rows.
- **Pixel art** at 16 px wants `pixelArt: true` and a whole-number camera zoom (the 2d-game skill); smooth art is drawn
  at its own size or smaller, never scaled up.

A picture Phaser's loader read goes in again through `assetChanged(path)` in phaser() (the 2d-game skill).

## In an app

On Apple's devices, an SF Symbol comes before any icon file. Kenney's icons and UI pieces suit a game's menus, a web
app or a page on a TV. An illustration in an app is `make_art`'s, in the app's own style. In a Swift app a fetched file
is in Assets/<pack>/, read with `LampAssets.url("<pack>/<file>")` or `LampAssets.image(…)`; a .glb in a Mac app's
RealityKit scene is turned into USD as the scene-3d skill says.

## Credit

Lamp writes each fetched asset into credits.json (its pack, author, license and files), which the app's info, its About
window, a shared copy, a published page and its repository's README all show: never take an entry out. CC-BY work asks
for more: name it where the game or app shows its credits too (a Credits line in the pause menu or the About screen:
"Taxi by Poly by Google, CC BY 3.0"), which the fetch answer reminds you of. CC0 needs nothing, though a line thanking
the pack's author is kind.

## When nothing fits

Make it in code, in the style of what's there, or with `make_art` for a picture. Lamp has no way to make a new model
from words yet: don't promise one.
