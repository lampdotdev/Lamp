---
name: game
description: Games, 2D or 3D, made either way - what makes one fun and playtesting it, the frame loop, controls (a controller, keys, touch, a TV remote), sound, saves, keeping every frame smooth and light rendering - with the tools for each (Lamp's game runtime in a web page, a Samsung or LG TV app's page, in 2D or with three.js, for a game played with phones, SpriteKit and Lamp's blocks in Swift, an integration's own), and turning an app into a game. Read before writing or changing a game.
---

# Games

A game is something played in real time, rather than used. What follows holds for every game, whichever way it's
made; each part then names the tools for each make. For a game in 2D, open the 2d-game skill too (Phaser or SpriteKit,
and which to choose); for one in 3D, the 3d-game skill (or scene-3d for RealityKit in Swift). Before designing its
opening, title, menus, level select, HUD, pause or results, read the game-ui skill: a new game picks its screen flow
there before any screen is drawn, however it's made.

The tools Lamp has for games:

- **Web**: Lamp's game runtime, `Web/lamp-game.js`, with Phaser for 2D (through `Web/lamp-phaser.js`) or three.js for
  3D, in a game `make_app_for` made with `kind` "game". It's a game's default make, 2D or 3D, wherever Lamp has a host
  for a page, and the same on every one of them. Read lamp-game.js first, all of it (and lamp-phaser.js for 2D): their
  comments are the whole interface. Below, "Web" means this runtime.
- **TypeScript**: a game whose source is TypeScript (one brought in from a Vite project, or when the person asks for
  it) keeps it in `src/` with `src/main.ts` as its entry, and Lamp bundles it into `Web/app/` before every build and
  look (types stripped, not checked): `Web/index.html` loads `app/main.js` (and `app/main.css` when the source imports
  CSS), and its import map names the bare imports, `three` and `lamp-game` (`./lamp-game.js`) among them. As in a
  Vite build, `import.meta.env` reads as a published build's, and a worker is a `src/**/*.worker.ts` file, started with
  `new Worker(new URL("./<name>.worker.js", import.meta.url), { type: "module" })` (`.js`: every file is bundled flat
  into `Web/app/`; a module worker, since what it shares with the page comes as an import). Edit `src/`,
  never `Web/app/`. A game in plain JavaScript stays as it is, its modules in `Web/`.
- **Phones as players**: a game on the runtime takes phones on the Wi‑Fi with `Lamp.controllers` (Web/lamp.js) and
  its page for them in Phone/ (the phone-controllers and phone-pages skills), on the Mac, in the TV preview, on a
  Samsung or LG TV and on the Xbox; elsewhere `Lamp.controllers` says it can't start, so the game stays whole with a controller,
  the keys or touch. Lamp's preview of the game plays with its scripted pad, and can join the game's phone page as one
  player (the phone-pages skill). Read a phone's buttons in `frame(f)` from `f.phones`, as the pads are read (`frame().phones`
  in a Phaser scene): one `{ player, down, pressed, released }` for each phone joined, each button by the name the phone
  page gave it, so `for (const p of f.phones) if (p.pressed.a) start()`. `pressed` and `released` last the one frame after
  it happened, and a press let go again between two frames is still a press. `onButton` runs between frames, so a flag
  it sets and `frame` clears is lost: keep it for what can't wait for a frame. Sticks and messages still come by
  `onAxis` and `onMessage`.
- **A TV app's page**: a game made as a Samsung or LG TV app before games took phones (`kind` "app") has no
  lamp-game.js: it follows the TV rules and lamp.js instead, with its own `requestAnimationFrame`. The rest of this
  skill holds for it wherever it doesn't name the runtime.
- **Native Apple** (Mac, iPhone, iPad, Apple TV): SpriteKit for 2D, SwiftUI for menus and scores, and Lamp's blocks
  in LampSupport.swift: a game made natively, where the person asked for that, it needs what only Apple's apps have
  (Game Center, a widget, a place inside an app of theirs) or the device has no host for a page (an Apple TV). It stays
  on Apple's devices: it can't go to Android, the Xbox, a TV's browser or the web later. For 3D in Swift, LampSceneView (the scene-3d skill) is for a Mac app made natively; a native 3D game
  on iPhone, iPad or Apple TV writes its own 3D with that device's frameworks (RealityKit or SceneKit).
- **Native Android**: Lamp has no game help in Kotlin yet: write the game's own frame loop on a SurfaceView or a
  Canvas, and its controls, sound and saves with Android's own APIs.
- **An integration's device** (Roku…): what its integration declares; read the device-integrations skill.
- **Apple Watch**: Lamp has no game help there.

## Fun

A game is for fun, and fun is designed from the first build, not added at the end:

- **A clear core loop.** One thing the player does again and again (jump, aim, steer, match) that feels good on its
  own, and a reason to do it once more: a score to beat, the next level, something new just ahead.
- **Quick feedback.** Every action answers at once, in sight and sound: a hit flashes and pops, a coin chimes and
  leaps to the score, a landing squashes. This is the game's juice: particles, a little screen shake on the big
  moments (never on every frame, and less on a TV across the room), a tween in place of a jump cut, a short freeze on
  a big hit.
- **A learning curve.** The first minute teaches by playing, never by a page of rules; then it gets harder in steps the
  player feels coming, with a breather after each rise.
- **Variety.** New enemies, places, rules or tools keep coming, so the tenth minute isn't the first again.
- **Surprise and delight the player frequently.** Small things nobody asked for: a character that waves back, a
  secret, a joke in a name, a combo that does something special, weather that changes, a celebration that's over the
  top. Many small ones beat one big one.

What's in it is made in code (3D models from three.js shapes, the 3d-game skill; pictures drawn in code or painted with
`make_art`) or ready-made from Lamp's free assets: models, characters with their animations, sprite sheets, tilesets,
textures, sound effects and music, fetched and credited by the `assets` tool (the assets skill says when each suits and
how to keep one style). Sound looks in those assets first ("Sound", below). Either way it's the person's to share. Any other file only when the person gives it or names where it comes from and its license allows sharing; it goes into the game's own
folder, credited as the rules say. The game never loads anything from the network while it's played.

When asked to make a game more fun, play it first and find what's flat (a loop that doesn't pull, a curve that's
too easy or too hard, an action that answers with nothing), then work on those four: the loop and the curve, the
juice, the surprises, and the variety. Keep what the person likes about it, and its controls.

## The frame loop

Everything that moves is moved by the time since the last frame, never by a fixed step per frame: devices draw at
different rates, and a slow frame must not slow the game.

- Web (the runtime): `game({ renderer, init, frame })` from lamp-game.js, moving by `f.dt`; in 2D, Phaser's scenes
  through `phaser({ scenes })` from lamp-phaser.js, moving by `update`'s `delta`, on the same one loop. Never requestAnimationFrame, timers, the
  clock, Math.random or localStorage: `random()`, `save()` and `load()` from the runtime let Lamp's preview replay a
  play exactly.
  Physics is the one exception to moving by `f.dt`: it steps at a fixed 1/60 s inside the frame, through `fixedStep`
  from lamp-game.js, so it behaves the same at any frame rate (Rapier for 3D, in the 3d-game skill).
- SpriteKit: in a SpriteView, one SKScene subclass for each screen with `scaleMode = .resizeFill`; movement in
  `update(_:)` scaled by the time since the last frame; collisions with SKPhysicsBody, its category and contact masks,
  and an SKPhysicsContactDelegate. An SKCameraNode follows the player through a world bigger than the screen.

## Controls

Controls follow the input the player has, not the device: the same player may pick up an Xbox, PlayStation or
Switch controller, the keyboard or the touch screen, and switch while playing.

- **Web**: lamp-game.js reads all of them as one pad, `f.pads[0]` (`pad()` in a Phaser scene). Write the controls once, as actions mapped to the
  pad (`const CONTROLS = { jump: BUTTON.A, pause: BUTTON.MENU, move: STICK.LEFT, gas: TRIGGER.RT }`), and read the pad
  through them. `input()` says what the player holds (`kind` is `controller`, with its `family`: `xbox`,
  `playstation`, `switch` or `other`; or `keyboard`, or `touch`); `onInput(draw)` draws now and again each time they
  take up another. Build every prompt and help screen inside it from the actions: `label(CONTROLS.jump)` is the
  button's name on that input ("A", "✕", "Space") and `glyph(CONTROLS.jump)` its badge, an element to put in the text.
  Both are null where the input has nothing for that action: leave the line out. Never write a key's or a button's
  name yourself; a page that reads the keys itself (`keyboard: false`) names its own keys by their codes,
  `label('KeyH')`.
- **Swift**: GameController's `GCController` for a controller, with the button's name from the controller itself
  (`localizedName`, `sfSymbolsName`) rather than a fixed letter; keys on a Mac with
  `NSEvent.addLocalMonitorForEvents`.
- **Touch**: big targets for thumbs, and few of them. Web: the runtime draws a stick and the buttons `touch` names;
  keep the game playable with those few.
- **A TV remote**: arrows and OK, and a back key; a game that needs more wants a controller, or phones (the
  phone-controllers skill).

B (or Esc, or Back) is the game's own back or cancel; Menu pauses.

## Sound

Every game has sound: a short effect (under a second) for each thing the player does or meets, and music only when it
suits, quiet (0.3 to 0.4) under effects at 0.6 to 0.8. Settings or the pause menu turn sound and music on and off.

**Look in the `assets` tool before writing any sound.** List what the game needs to sound like (each thing the player
does or meets, and its music), then see the whole catalog: `assets` with `kind: sound`, `limit: 30` and no `find` lists
every effect, and `kind: music` every loop. Fetch one for every moment it can serve, by name and notes (the assets
skill's "Sounds and music" has more). Only files the person gave come before this. Write a sound in code only for a
moment nothing in those lists fits, or one that has to follow the game as it's played (an engine's pitch, notes on a
scale), and name each of those in your report. They're chosen as the game is made, and every one ships inside it.

- Web: `sound` in lamp-game.js. A file loads with `await sound.load('assets/…')`. Written in code, effects come from
  `sound.tone`, and music from a loop of a few bars written out note by note into `sound.samples` (a bass line, chords,
  a melody, in one key). Either way `sound.play` plays an effect and `sound.music` a loop, a calmer one for menus and a
  livelier one for play.
- Swift: files in Assets/ (.wav, .m4a or .mp3, and what the `assets` tool brought in) play with an
  `AVAudioPlayer(contentsOf: LampAssets.url(name)!)` made once and `prepareToPlay()`ed, a few of them for an effect
  that overlaps itself; music is one looping (`numberOfLoops = -1`). Written in code, effects come from one
  `AVAudioEngine` started at launch with an `AVAudioPlayerNode`, each effect a few hundredths of a second of a wave
  written once into an `AVAudioPCMBuffer`, with soft ends so it doesn't click. On iPhone set the session to
  `.ambient`, so the silent switch mutes the game and the person's own music keeps playing.

## Saves

Scores, progress and settings are kept on the device, and only ever added to: a new field gets a default where it's
read, so an update never loses a player's progress. Web: `save(name, value)` and `load(name)` from lamp-game.js.
Swift: LampStore.

## Changes while it's played

Lamp puts each change into the game while the person plays it (Web: lamp-game.js, "Changes while it's played"), so a
game is written to keep the player's place through one:

- **Everything that has to last is registered, by name, once.** That's how every new game is written, and the scaffold
  starts that way. Web, with `const live = hot(import.meta)` from lamp-game.js:

  ```js
  const renderer = live.renderer(() => new THREE.WebGLRenderer({ antialias: true }));
  const camera = live.camera('main', () => {
      const c = new THREE.PerspectiveCamera(60, 16 / 9, 0.1, 500);
      c.position.set(0, 4, 12);   // its starting pose and lens are made here, and nowhere else
      return c;
  }, { target: () => controls.target });
  const play = live.state('play', {
      version: 1,
      start: () => ({ mode: 'opening', menu: null, level: 1, score: 0, lives: 3, player: { x: 0, z: 0, heading: 0, speed: 0 } }),
  });
  ```

  - `live.renderer(build)`: new code gets the renderer the game has before it could make another, so there's one, with
    its compiled shaders. It's made again only when `build` itself changes. An async build (the 3d-game skill's
    WebGPU) is awaited.
  - `live.camera(id, build, { target })`: keeps the camera's pose, lens and what it looks at (`target` gives anything
    with x, y and z that new code makes again, as OrbitControls' `target`). At the first frame it's where the player
    left it, whatever the start set. A change to `build` gives the new lens at the old pose.
  - `live.state(id, { version, start, migrate })`: everything that says where the game is goes in one plain object,
    the mode (playing, paused, a menu), which menu, overlay or card is open, the level, the player's position, heading
    and speed, what they ride or hold, the score, lives, the clock, the time of day. Change its fields and never
    replace it. Lamp snapshots it as plain JSON by itself, so it holds no objects of three.js or Phaser, and nothing
    derived from it is kept elsewhere. A field added to `start()` takes its start value, and every other field keeps its value.
    Raise `version` when a field changes its meaning, with `migrate(old, oldVersion)` to carry the old state over; with
    none, that state starts over from `start()`.
  - Each part of the world is kept with `live.keep` (below).

  Only what's registered is kept. A renderer or camera the game's code makes for itself, or a variable of its own,
  starts again with the code.
- **One start path.** Everything registered is back before `init` runs and before the first frame, at a fresh start
  it's `start()`, and the same object stays the whole time. So `init` (in a 2D game, the first scene's `init` or
  `create`) reads the state and builds exactly that screen: that mode, that menu or overlay open, and nothing a fresh
  start shows (a title card, an intro, a tutorial prompt, a fade in) built or shown at all. Never start fresh and then
  put the place back, which leaves the opening over the game and input in the opening's mode. A later restart (a new
  round, a death) sets the state's fields back itself. A 2D game registers its state; Phaser's game and cameras are made
  again from it.
- **A game from before this**, or one brought in, may use `snapshot()` in game() (or phaser()), plain JSON of where it
  is, with `pendingRestore()` (the state while it starts, null for a fresh start and once it has started) or
  `restore(state)` (called after init when it didn't read pendingRestore()). They're still taken, and a change keeps
  its place through them. Without either it starts again, from its saves. When you're asked to change such a game, register what your change
  touches as you make it, and leave the rest for the changes that touch it: move its renderer into `live.renderer` first, its
  main camera into `live.camera`, then its state, field by field out of snapshot() into `live.state`.
- **Lamp checks and says.** With your request comes what the game hasn't registered. A change that would start play over
  (no state registered, and no snapshot() it reads back) waits for the person's Reload rather than going in, and the
  look names what's missing: register it in the same turn, and Reload takes both in. Those are the one change a game
  needs to adopt this: after that, changes go in as it's played. After a run of the code, a look says what was kept, built again and reset,
  and what isn't registered. Anything reset that you didn't mean to reset is the place the person lost: register it
  now, so the next change keeps it.
- A game with phones keeps them through all of this: they stay joined with their numbers, and the code never stops or
  starts `Lamp.controllers` for a change. So the state holds which player owns which slot (the seat, side, color or
  team each player number has), and the new code restores those slots before it sits anyone down. As its first frame
  nears, `onLeave` and `onJoin` are called again for who left and who is here, so `onJoin` for a player who already has
  a slot leaves the slot alone, and only a new player takes a free one. What a phone has held down stays in
  `f.phones`' `down`; a press or message from before the new code started isn't sent again and isn't in `pressed`, so
  anything read while held is read from `down` (or `isHeld`), not remembered from `onButton`.
- Pictures, models, sounds and data load through the runtime (`texture()`, `model()`, `sound.load()`, `asset()`), never
  by a URL of the game's own: a new copy of one of those goes into the running game with no reload. What the game makes
  of a file itself (a material from shader source, clones of a model, a mixer for its animations, a level from JSON) is
  made again in `assetChanged(path)`, which returns true when it has.
- Code goes into the running game too, never by opening the page again, in one of two ways, and the log says which,
  what was kept and how long it took:
  - **Swapped**, at once: a change to the methods of a class in a module that ends with `hot(import.meta).accept()`
    from lamp-game.js. Every object the game made of that class runs the new methods with its fields kept.
  - **Run again in place**, for anything else (the HTML, the module that starts the game, a class's constructor or
    fields, an exported function, a new module): the page is put back as the new HTML has it, every module of the game
    runs again, and the game starts straight from what it registered, as a reload would but without one. What's
    registered stays: the renderer and its compiled shaders, the cameras, the state, and each part kept with
    `hot(import.meta).keep(key, build, { inputs, from })`, and so do the files the runtime loaded, so the change costs only
    what's built again. The listeners,
    timers, sound contexts and workers the old code started are taken away by Lamp, and so are its `Lamp.controllers`
    callbacks, which the new code sets again as it starts; `dispose` in game() is for anything else it must let go of,
    and never stops the phones (a `stop()` there is ignored).

  So a game is written in parts, each in a module of its own:

  - **The module that starts the game only puts the parts together** (`game.js`; New York's `main.js`). It registers
    the renderer, the cameras and the state, and keeps each part of the world:

    ```js
    import { game, hot } from './lamp-game.js';
    const live = hot(import.meta);
    const renderer = live.renderer(() => new THREE.WebGLRenderer({ antialias: true }));
    const ground = live.keep('ground', () => buildGround());
    const trees = live.keep('trees', () => buildTrees(ground.heights), { inputs: [ground] });
    scene.add(ground.group, trees.group);
    ```

    A kept part is built again only when its own module (or one it imports) changed, its build function changed, one
    of its `inputs` (the parts it's built from) was built again, or a file it read as it was built changed. So build
    each part of the world (the ground, the buildings, the trees and street details, the props, the traffic) in a
    module of its own, into a group of its own that's added to the scene at each start, and do everything to it
    (setting it on the ground, cutting it for culling) inside its build, never to a kept part afterwards. The build
    function in the starting module names the module it builds from (`buildTrees`), since that's how Lamp tells which
    change is its own. Declare the data each part is built from in its `from` (files beside the page, a module of
    generated data, or a folder ending in /), so a change to that data builds the part again in place, with the rest
    of the world and the player's place kept:

    ```js
    const streets = live.keep('streets', () => buildStreets(), { from: ['js/map-data.js'] });
    const paint = live.keep('roadPaint', () => buildRoadPaint(streets.network), { inputs: [streets], from: ['js/map-data.js'] });
    ```

    After a run, the look says which parts were built again, how long each took, and what of the change nothing read
    again, which shows only after Reload. A look in the hidden copy builds every part afresh, so it shows a change the
    open game may not: what you see there is in the person's game only when the part it's built into was built again.

    A big 3D world on three.js's `WebGPURenderer` keeps its scene and lights the same way, as its camera is. For a new one of
    them it works out how to draw every object again, which holds a big world still for a second at each change. Empty
    the kept scene at each start (`scene.clear()`), then add back the kept lights and each part's group, so what the
    last run added doesn't stay.
  - **The HUD and menus are made at each start**, from the page's HTML or built in code, and their elements found
    there (in init, or the function that starts the game), never once at a module's top level: the page they find is
    the one the new HTML put back.
  - **What changes as the person plays is a class the game makes an object of** (a vehicle and its tuning, the
    player's moves, missions, enemies, the HUD's code, the camera, a shader's settings), its state in the object and
    the module ending with `hot(import.meta).accept()`, so most changes are swapped:

    ```js
    import { hot } from '../lamp-game.js';
    const CAR = { topSpeed: 36, acceleration: 4.5 };   // tuning, read where it's used
    export class Car {
        constructor(scene) { this.mesh = buildCar(); scene.add(this.mesh); this.speed = 0; }
        update(dt, pad) { this.speed = Math.min(CAR.topSpeed, this.speed + pad.rt * CAR.acceleration * dt); … }
    }
    hot(import.meta).accept();
    ```

    Export every class a module defines and the game calls (one kept to itself keeps its old methods), read tuning
    where it's used rather than copying it into fields in the constructor, and keep state in the objects, not in
    variables at the module's top. An exported plain object (`export const TUNING = {…}`) takes the values a change
    changed and keeps the rest. What a constructor built once stays as built through a swap: give
    `accept((next, { changed }) => …)` the rebuild, or have it return false to run the code again.
    `hot(import.meta).dispose(data => …)` takes away what a version made at its top level, keeping in `data` what the
    next version reads as `hot(import.meta).data`.

  A stylesheet is swapped by itself. Where running again can't be done (a change to the import map or to a script that
  isn't a module, modules that import each other in a circle) the change waits for the person's Reload, which opens the
  page again from what's registered; so does new code that fails as it starts, before its first frame or in its first
  second, at once. A game bundled from TypeScript is one
  file, so its changes run it again, and what it keeps is built again with each change.
- `busy()` is true while a match, race or round is on: a change that runs the code again then waits for the next
  pause, and the person can put it in at once with Reload. A swap goes in at once.
- On a phone, Android, a TV or the Xbox a change arrives when Lamp installs the game again, and the runtime puts what's
  registered back then, once, as it does the last snapshot.

Swift: a change reopens the app; what it keeps is what it saved.

## Keeping every frame smooth

A frame has about 16 ms, and anything that runs during play takes from it, so a slow piece is a stutter:

- load each picture, model and sound once and reuse it; prepare a level before it starts;
- reuse what comes and goes (bullets, enemies, particles) rather than making new ones each time;
- allocate nothing per frame, and keep per-frame work to what moves;
- many copies of one thing are one draw (THREE.InstancedMesh, `LampScene.copies` in a Mac-only app).

The request's device line names the slowest device the game is played on and its budget; the log says how frames kept
to time. When frames are late, draw less.

## The look

Sprites, characters and backgrounds are art from `make_art` or one ready-made pack (the assets skill), all in one
style, on a transparent background where they move. Shapes and colors made in code, well lit, look better than
mismatched models. Score, pause and menus are large and easy to read, over the game (SwiftUI over a SpriteView; HTML
over the canvas in a page), and made for its world: the game-ui skill says how to choose the screens a game needs and
give them its theme.

After changing anything that moves, look_at_app with `motion` shows what changes frame to frame and catches flicker a
single picture hides.

## Playtesting

Play it the way the person would before you finish: a game that only looks right isn't done. Web: Lamp's preview
plays the game from a script of the controller's moves (`use_app` with `stick`, `button` and `wait`), with the same
random numbers each time, so the same moves after a change show exactly what it changed. Play a whole round: start,
learn the controls, score, get hit, lose, win, pause. Ask of each stretch whether it's fun: is there always something
to do, does each action answer, is it too easy or too hard, does anything surprise. Fix what isn't, and play it again.

## A game and the wish's other apps

When the person wants an app to become a game ("actually, make it a game"), change its code in place: the same app,
now played. If they might want both (the app they use and a game beside it), ask once whether to keep the app as well
or replace it. Turning it into a game is a change to that app: `make_app_for` with its folder in `app` and `kind`
"game" (made as the table's defaults say unless the person names a make: web wherever Lamp has a host for a page),
keeping its folder and data, and its code changed into a
game. A game beside
the app is one more app, only when they say they want both and the game is of another kind than the app:
`make_app_for` with `another` and `kind` "game", in a folder of its own, once they chose that when you asked. Two apps
of one kind can't be in one wish yet (the `more-apps` skill), and a game is never made web only to get around that. A
game that becomes an app again is the same in reverse.
