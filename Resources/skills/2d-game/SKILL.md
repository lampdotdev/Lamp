---
name: 2d-game
description: 2D games - choosing 2D or 3D, and Phaser (a game of Lamp's game kind, played on the Mac, iPhone and iPad, Android, TVs and the Xbox) or SpriteKit (a Mac or iPhone app); scenes, the frame step, cameras, tilemaps, sprite sheets, physics, controls on every input, pixel art, TV safe areas, sound, saves, drawing the art, and keeping it smooth on the slowest place. Read before writing or changing a 2D game.
---

# 2D games

A 2D game is drawn flat: a platformer, a shooter seen from above or the side, a racer seen from above, a puzzle or
arcade game played in real time. Read the game skill too: what every game needs (moving by the time since the last
frame, controls, sound, saves, the look) is there, and this skill is how to do it in 2D.

## 2D or 3D

2D when the person describes something flat (a platformer, "like Mario", "like Pac-Man", a top-down shooter, a pixel-art
game, a puzzle with falling pieces) or a game whose look is drawings rather than a world to look around. 3D when they
want depth to move through (driving through a city, flying, a first-person view, a ball rolling over hills): the
3d-game skill. When nothing says, a game whose play is flat is better flat: it's cheaper on every device and drawings
read better than simple 3D shapes. Don't ask; choose, and say in a sentence which.

## Phaser or SpriteKit

- **Phaser**, in a game of Lamp's game kind: the page in Web/ on Lamp's game runtime. It's played on the Mac and goes,
  unchanged, to an iPhone or iPad, an Android phone, tablet or TV, a Samsung or LG TV, the Xbox and a page on the web,
  whenever the person asks for one of those later. This is the default for a 2D game.
- **SpriteKit**, in a Mac or iPhone app written in Swift: when the game belongs with Apple's own things (Game Center,
  a widget, iCloud, the Apple Watch), sits inside an app of theirs (a game in a menu of their Mac app), or is for an
  Apple TV, which runs no pages. A SpriteKit game can never go to Android, the Xbox, a Samsung or LG TV or the web: it
  would have to be written again. Say so plainly when choosing it, and choose it only for what needs it.

The kind of app is chosen before your first turn: a game is of the game kind, and a Mac or iPhone app whose request is
a game is written with SpriteKit. When the choice doesn't fit (a game of the game kind that needs Game Center, or a Mac
app that should be playable on the person's Xbox), say why in a sentence and change it with make_app_for.

## Phaser on Lamp's runtime

Lamp's game kind runs Phaser 3 (3.90) through `Web/lamp-phaser.js`, over the runtime in `Web/lamp-game.js`. Read both,
all of them, before writing the game: their comments are the interface. Lamp puts Phaser in `Web/phaser` once the page
imports it.

index.html keeps the scaffold's head (lamp.js, then the import map, whose `phaser` entry is
`./phaser/phaser.esm.min.js`), then `<script type="module" src="game.js">`. game.js:

```js
import * as Phaser from 'phaser';
import { phaser, pad } from './lamp-phaser.js';
import { BUTTON, STICK, sound, save, load, random, log, label, glyph, onInput, pendingRestore } from './lamp-game.js';

const CONTROLS = { move: STICK.LEFT, jump: BUTTON.A, back: BUTTON.B, pause: BUTTON.MENU };

class Play extends Phaser.Scene {
    constructor() { super('play'); }
    preload() { this.load.image('hero', 'art/hero.png'); }
    create() { … }
    update(time, delta) {
        const p = pad(), dt = delta / 1000;
        if (p.pressed & CONTROLS.jump) …
    }
}

phaser({ scenes: [Boot, Title, Play], physics: { default: 'arcade', arcade: { gravity: { y: 2400 } } }, touch: BUTTON.A | BUTTON.B | BUTTON.MENU });
```

What Lamp has changed in Phaser, so its usual code works here:

- **One frame loop, Lamp's.** Phaser's own loop is asleep; each of the runtime's frames steps Phaser once. Use a
  scene's `update(time, delta)` (ms) and Phaser's timers and tweens freely: they all run on that one clock, which in
  the preview is exactly 1/60 s a frame. Never requestAnimationFrame, setTimeout, Date or Math.random of your own:
  `random()` from lamp-game.js, or `Phaser.Math.RND`, which Lamp seeds from it.
- **Input is the runtime's pad.** `pad()` is the first controller with the keyboard and the touch controls merged in
  (lx, ly, rx, ry with up positive; buttons as BUTTON bits in down, pressed and released). Phaser's keyboard and
  gamepad are off: `this.input.keyboard` and `this.input.gamepad` are null, so never `createCursorKeys` or
  `addKey`. Phaser's pointer input works with the mouse on the Mac; on a touch screen Lamp's touch controls lie over
  the canvas, so a game played by tapping the screen itself passes `touch: false` and reads `this.input.on('pointerdown')`.
- **Sound is the runtime's.** Phaser's sound is off: `this.load.audio` and `this.sound` play nothing. Make effects with
  `sound.tone` in a scene's `create` (or once, at the top of game.js), or load files with `await sound.load('hit.wav')`.
- **The stage is 1920x1080**, fitted to the window or screen with black around it. Lay everything out in those units.
  The page is never resized to the window: don't listen for resize.
- **Loading.** Load each scene's files in its `preload`, best all in a first Boot scene, and start play from `create`.
  The preview waits for loading to finish, so a play is the same frames every time; on a device it takes what it takes,
  so a scene that loads mid-game shows a loading line rather than nothing.

### Structure

- **Scenes**: one for each screen (Boot, which loads; Title; Play; GameOver). A pause menu is a scene launched over
  play (`this.scene.launch('pause'); this.scene.pause()`), which reads the pad itself and resumes play
  (`this.scene.resume('play'); this.scene.stop()`). Keep the game's state (score, lives, level) in a plain object
  passed in `this.scene.start('play', state)`, not spread over scenes.
- **The step**: move by `delta`, and give Arcade physics the work of falling, sliding and colliding. Arcade steps its
  world at a fixed 60 times a second whatever the screen's rate (its `fps`, the default), so jumps reach the same
  height on a 120 Hz Mac and a 50 Hz TV. Game logic that must be exact (a puzzle's grid, a rhythm) counts in its own
  fixed steps from `delta`.
- **Cameras**: `this.cameras.main.setBounds(0, 0, worldWidth, worldHeight)` and `startFollow(hero, true, 0.12, 0.12)`
  with a deadzone (`setDeadzone(300, 200)`), so the screen doesn't jerk with every step. Shake and flash
  (`shake(120, 0.006)`, `flash(150)`) for hits, briefly. The HUD is a second camera's, or HTML over the canvas, never
  moved by the world's camera (`setScrollFactor(0)` on what's drawn in the scene).
- **Tilemaps**: write each level as rows of characters in code (`'..........#####....'`), each a tile, and build it with
  `this.make.tilemap({ data, tileWidth: 64, tileHeight: 64 })`, `map.addTilesetImage('tiles')` and `map.createLayer(0,
  tileset)`, with `layer.setCollision([...])` and `this.physics.add.collider(hero, layer)`. Rows in code are easy to
  read and change; there's no level editor here. Make the tileset image in code (below) so every tile is the same size.
- **Sprite sheets and atlases**: frames of one character or thing in one image, `this.load.spritesheet('hero',
  'art/hero.png', { frameWidth: 64, frameHeight: 64 })`, played with `this.anims.create({ key: 'run', frames:
  this.anims.generateFrameNumbers('hero', { start: 0, end: 5 }), frameRate: 12, repeat: -1 })`. Many small pictures in
  one texture draw in one batch: that's what keeps a busy screen cheap. Pictures made in code are drawn into one
  texture too (`this.textures.createCanvas`, then `texture.add(name, 0, x, y, w, h)` for each frame).
- **Physics**: Arcade for nearly every game: boxes and circles, gravity, velocity, `collider` and `overlap` with a
  callback. A platformer's player is `this.physics.add.sprite` with `setCollideWorldBounds(true)`; it may jump while
  `body.blocked.down`, with a few frames' grace after leaving a ledge and a jump pressed just before landing still
  taken. Matter (`physics: { default: 'matter' }`) only when things must tumble, stack, swing on joints or have real
  shapes (a physics puzzle, a pile of crates): it costs far more a body and its bodies don't stand still as simply.
- **Many of a thing** (bullets, coins, enemies, sparks): a group made once with `maxSize` and taken from with
  `group.get(x, y)`. A physics group's member is put back with `disableBody(true, true)` and taken out again with
  `enableBody(true, x, y, true, true)`: hidden and inactive alone, its body still collides and overlaps, so a
  collected coin is collected again and a spent bullet still hits. Sprites without bodies are put back with
  `setActive(false).setVisible(false)`. Particles come from one emitter (`this.add.particles`) with a modest
  `maxParticles`.

### Controls on every input

Write the controls once as actions on the pad (CONTROLS above) and read the pad through them. The runtime gives a
controller, the keyboard and the touch controls as that one pad, so the game needs nothing else. Show how to play, and
every prompt, from the actions: as HTML over the canvas inside `onInput(draw)`, with `glyph(CONTROLS.jump)` in the
text ("Press [A] to jump", a badge as the player's input draws it), or in a Phaser Text with `label(CONTROLS.jump)`
("A", "✕", "Space"), redrawn from `onInput`. Leave a line out where `label` is null. On a phone the touch controls show
a left stick and the buttons `touch` names: give a platformer jump on A and perhaps one more, and keep the game whole
with those few. Menus move with the stick or the d-pad, choose with A and go back with B; Menu pauses.

### Pixel art or smooth

- **Pixel art**: `phaser({ pixelArt: true, … })` keeps every pixel sharp, and the camera zooms by a whole number so
  each art pixel is the same number of screen pixels: `this.cameras.main.setZoom(4)` shows a 480x270 world on the
  1920x1080 stage (`setZoom(6)` 320x180). Draw the art at that small size, and place things on whole pixels. Never
  scale pixel art by a fraction, or some pixels come out wider than others.
- **Smooth** (drawings, painted art, vector shapes): leave `pixelArt` off, draw at the size things appear on the
  1920x1080 stage, and scale pictures down rather than up.

### Safe areas

On a TV the edge of the picture may be cut off: keep the score, lives and prompts inside the middle 90% of the stage
(96 px in from the sides, 54 from the top and bottom), and anything the player must see there too. On a phone Lamp's
touch controls sit in the bottom corners and small buttons in the top corners: put the HUD at the top center or along
the top edge between them, never under a thumb.

### Drawing the art

Nothing is loaded from the network, ever: the art is in Web/ or made in code.

- **Ready-made sprite sheets and tilesets** from the `assets` tool: a platformer's characters with their walk, jump
  and hurt frames, enemies, coins, tiles, a space shooter's ships, a top-down racer's cars and track, pixel-art towns
  and dungeons, UI and icons, each pack in one style. Before drawing a game's characters, enemies and tiles, look
  there (`find` with `show`): a pack's matching frames are what code and `make_art` struggle to give. Open the assets
  skill to choose and to load an XML atlas or a tilesheet with spacing.

- **Shapes made in code** are the quickest and always match: draw once with `this.make.graphics({ add: false })`
  (rectangles, circles, rounded boxes, polygons, a gradient of bands) and `generateTexture('coin', 48, 48)`, in a
  Boot scene, then use the texture like any picture. A palette of four to eight colors, used everywhere, makes a game
  look made.
- **Pixel art in code**: `this.textures.generate('hero', { data: ['..33..', '.3333.', …], pixelWidth: 4 })` draws a
  picture from rows of palette digits (Phaser's 16-color palette, or give `palette`), a frame per call; it's the way to
  get a character's frames the same size and style.
- **Pictures from `make_art`**: for a character, an object or a background in the style of the game's icon, cut out
  on a transparent background (with `scene` for a whole backdrop). It saves into Assets/: copy what the game uses into
  Web/art/ (`cp Assets/hero.png Web/art/`) and load it from there. Each picture stands alone, so it suits a hero, a
  boss, an item or a backdrop rather than animation frames: move one with tweens (a bob, a squash on landing, a tilt as
  it runs) instead of frames that wouldn't match. Make it once and scale it in the game (`setDisplaySize`).
- A file the person gave (Attachments/) is copied into Web/ the same way.

### Sound and saves

The game skill's: effects from `sound.tone` for each thing the player does or meets (a jump sliding up, a coin's two
quick notes, noise for a hit), made once; music quiet or none. The best score, levels reached and settings with
`save(name, value)` and `load(name)`, read with a default for anything new (`load('best') ?? 0`).
`snapshot()` in phaser() keeps the player's place through a change (the scene, its mode, which menu or DOM card is
open, the player's position, the score, the time), and `busy()` holds a change of code during a round (the game skill,
"Changes while it's played"). The first scene reads `pendingRestore()` and goes straight to the scene the snapshot
names, and that scene's `create` reads it again and builds that place with no title card or intro, so a fresh start
and a change's start are one path:

```js
class Boot extends Phaser.Scene {
    constructor() { super('boot'); }
    preload() { … }
    create() { this.scene.start(pendingRestore() ? 'play' : 'title'); }
}
class Play extends Phaser.Scene {
    constructor() { super('play'); }
    create() {
        const was = pendingRestore();          // null on a fresh start and on every restart after the game began
        this.level = buildLevel(was ? was.level : 1);
        this.mode = was ? was.mode : 'ready';
        if (was && was.paused) this.showPause(); else if (!was) hud.card('Level 1');
    }
}
```

Read it in `create`, not from the scene's data: `this.scene.restart()` with no data starts the scene with its last
data again, so a snapshot passed that way would be put back on every restart. A picture Phaser's loader read goes in again through `assetChanged(path)` in phaser() (load it again and
swap the texture), or the page opens again with the snapshot.

### Keeping it smooth on the slowest place

The slowest places are an Xbox One in Developer Mode, a cheap Android phone or TV stick and a Samsung or LG TV's
browser; the request's device line names the slowest this game is played on and its budget, and the preview's stats
count draws a frame (`look_at_app`). In 2D what costs is draws and filling the screen, rarely shapes:

- few textures: sprites that share one texture (an atlas, or the shapes made into one canvas texture) are drawn in
  one batch, and every change of texture starts another;
- a Text object redraws its whole picture when its text changes: change it only when the number does, never every
  frame (or use HTML over the canvas for the HUD);
- a Graphics object drawn in play is redrawn every frame: make it a texture once instead;
- layers of big pictures over the whole screen (parallax backgrounds, a full-screen overlay) each fill the screen
  again: two or three at most on a TV;
- effects (`preFX`, `postFX`, glow, blur, bloom) are full extra passes: none on a TV or an Xbox One;
- no allocation per frame, and pools for what comes and goes; Arcade rather than Matter.

The log on a device says every ten seconds how many frames a second it gets there: when it's short of 60, draw less.

### Checking it

`look_at_app` plays the game in the preview from its start and shows its last frame; `use_app` plays on with the
controller (`stick`, `button`, `wait`), a picture after each, and every look plays the whole thing again with the same
moves. Play it as the person would: start it, jump, die, win, pause, change a setting and come back to find it kept.
Once it plays right, `look_at_app` with `on_device` where Try On points.

## SpriteKit in a Mac or iPhone app

The game is an `SKScene` subclass for each screen, shown in SwiftUI with `SpriteView`, with SwiftUI over it for the
score, menus and prompts:

```swift
import SwiftUI
import SpriteKit

struct GameScreen: View {
    @State private var scene = PlayScene(size: CGSize(width: 1920, height: 1080))
    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .overlay(alignment: .top) { ScoreBar(score: scene.score) }
    }
}
```

Make the scene once (`@State`), never in `body`. A scene of a fixed size with `scaleMode = .aspectFit` is laid out
once and letterboxed on any window, like the game kind's stage; `.resizeFill` with an `SKCameraNode` following the
player shows more of a big world on a big window. What SwiftUI shows over it (the score, lives, a pause) comes from
the scene as `@Observable` (Observation), which `@State` holds as above; a scene that is an `ObservableObject` with
`@Published` values is held with `@StateObject` instead, or the view never sees them change.

- **The step**: `update(_ currentTime:)` works out the time since the last frame (at most 1/20 s, so a pause doesn't
  jump) and moves by it; physics bodies move themselves. Logic that must be exact counts fixed steps of 1/60 s from it.
- **Cameras**: an `SKCameraNode`, `scene.camera = cam`, moved toward the player each frame (`cam.position +=
  (target - cam.position) * min(1, dt * 8)`) and kept inside the level; the HUD is SwiftUI, or nodes added to the
  camera.
- **Tiles**: for a level of rows in code, a sprite per tile is fine to a few thousand; past that, draw the level's still
  part once into one texture (`view.texture(from: node)`) and show that. `SKTileMapNode` with a tile set made in code
  works too, for a big grid.
- **Sprite sheets**: one picture cut into frames with `SKTexture(rect:in:)` (the rect in 0-1 of the sheet), played with
  `SKAction.animate(with:timePerFrame:)`. Textures of one `SKTextureAtlas`, or cut from one sheet, draw in one batch.
- **Physics**: `SKPhysicsBody(rectangleOf:)` or `(circleOfRadius:)`, each with its `categoryBitMask`,
  `collisionBitMask` and `contactTestBitMask`, and the scene as `physicsWorld.contactDelegate` hearing
  `didBegin(_:)`. A platformer's ground is one body for each run of tiles side by side, not one per tile, so the player
  doesn't catch on the seams; give the player `allowsRotation = false` and set its velocity rather than pushing it.
- **Controls**: a controller through GameController, read each frame from `GCController.current?.extendedGamepad`
  (`leftThumbstick`, `dpad`, `buttonA`…, and `buttonMenu` to pause); on the Mac the keys with
  `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp])`, keeping the keys held in a set and returning nil
  for the game's keys (so they don't beep); on an iPhone, touch: `GCVirtualController` with a left stick and one or
  two buttons draws them over the game and reads as a controller, so one reading covers both. Name a controller's
  buttons from the controller itself (`buttonA.sfSymbolsName` as an `Image(systemName:)`, or `localizedName`), never
  a fixed letter, and keys by the key ("Space", "←").
- **Pixel art**: `texture.filteringMode = .nearest` on every texture, positions rounded to whole pixels, and the scene
  scaled by a whole number.
- **Sound and saves**: as the game skill says for Swift (effects made once with AVAudioEngine, `.ambient` on iPhone),
  and the best score and settings in LampStore.
- **Game Center** (`GKLocalPlayer.local.authenticateHandler`, leaderboards) works only in an app signed for the
  person's Apple team with Game Center on: keep the game whole without it, scores in LampStore as well.
- **Art**: as above: shapes in code (`SKShapeNode` drawn once into a texture with `view.texture(from:)`, since a shape
  node is costly to draw), pictures from `make_art` in Assets/ loaded once with `LampAssets.image("hero.png").map(SKTexture.init(image:))`.

Look with `look_at_app` (with `motion` for what moves) and use it with `use_app` as the person would, keys and clicks;
the game skill's "Keeping every frame smooth" holds here too.
