---
name: game
description: Games, 2D or 3D, made either way - what makes one fun and playtesting it, the frame loop, controls (a controller, keys, touch, a TV remote), sound, saves, keeping every frame smooth and light rendering - with the tools for each (Lamp's game runtime in a web page, a Samsung or LG TV app's page, in 2D or with three.js, for a game played with phones, SpriteKit and Lamp's blocks in Swift, an integration's own), and turning an app into a game. Read before writing or changing a game.
---

# Games

A game is something played in real time, rather than used. What follows holds for every game, whichever way it's
made; each part then names the tools for each make. For a game in 2D, open the 2d-game skill too (Phaser or SpriteKit,
and which to choose); for one in 3D, the 3d-game skill (or scene-3d for RealityKit in Swift).

The tools Lamp has for games:

- **Web**: Lamp's game runtime, `Web/lamp-game.js`, with Phaser for 2D (through `Web/lamp-phaser.js`) or three.js for
  3D, in a game `make_app_for` made with `kind` "game". It's a game's default make, 2D or 3D, wherever Lamp has a host
  for a page, and the same on every one of them. Read lamp-game.js first, all of it (and lamp-phaser.js for 2D): their
  comments are the whole interface. Below, "Web" means this runtime.
- **Phones as players**: a game on the runtime takes phones on the Wi‑Fi with `Lamp.controllers` (Web/lamp.js) and
  its page for them in Phone/ (the phone-controllers and phone-pages skills), on the Mac, in the TV preview, on a
  Samsung or LG TV and on the Xbox; elsewhere `Lamp.controllers` says it can't start, so the game stays whole with a controller,
  the keys or touch. Lamp's preview of the game has no phones: its scripted pad is the player there.
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

What's in it is made in code (3D models from three.js shapes, the 3d-game skill; music and effects from `sound`,
below; pictures drawn in code or painted with `make_art`) or ready-made from Lamp's free assets: models, characters
with their animations, sprite sheets, tilesets and textures, fetched and credited by the `assets` tool (the assets
skill says when each suits and how to keep one style). Either way it's the person's to share. Any other file only
when the person gives it or names where it comes from and its license allows sharing; it goes into the game's own
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

- Web: `sound` in lamp-game.js, effects made in code with `sound.tone` unless the person gave files. Music is made in
  code too: a loop of a few bars written out note by note into `sound.samples` (a bass line, chords, a melody, in one
  key) and played with `sound.music`, a calmer one for menus and a livelier one for play.
- Swift: files the person gave go in Assets/ (.wav, .m4a or .mp3) and play with an
  `AVAudioPlayer(contentsOf: LampAssets.url(name)!)` made once and `prepareToPlay()`ed, a few of them for an effect
  that overlaps itself; music is one looping (`numberOfLoops = -1`). With no files, make effects in code: one
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

- `snapshot()` in game() (or phaser()) returns, as plain JSON, everything that says where the game is: the mode
  (playing, paused, a menu), which menu, overlay or card is open, the level, the player's position, heading and speed,
  what they ride or hold, the camera, the score, lives, the clock, the time of day.
- The new code starts straight from it. `pendingRestore()` from lamp-game.js gives the snapshot while the game starts
  (in `init`; in a 2D game in its first scene's `init` or `create`), or null for a fresh start, and null again once
  the game has started, so a later restart (a new round, a death) is fresh. With a state, the game builds exactly that
  screen: that mode, that menu or overlay open, and nothing a fresh start shows (a title card, an intro, a tutorial
  prompt, a fade in) built or shown at all. One start path, given the state or not, is the pattern: never start fresh
  and then put the place back, which leaves the title over the game and input in the title's mode. Keep snapshot()
  current as state is added, and let the start take an older snapshot: a field it lacks keeps its start value. Without
  a snapshot a change of code starts the game again, from its saves. (`restore(state)`, called after init when the
  game didn't read pendingRestore(), is still taken from games written that way; a new game reads the state at start.)
- Pictures, models, sounds and data load through the runtime (`texture()`, `model()`, `sound.load()`, `asset()`), never
  by a URL of the game's own: a new copy of one of those goes into the running game with no reload. What the game makes
  of a file itself (a material from shader source, clones of a model, a mixer for its animations, a level from JSON) is
  made again in `assetChanged(path)`, which returns true when it has.
- `busy()` is true while a match, race or round is on: a change of code then waits for the next pause, and the person
  can put it in at once with Reload.
- On a phone, Android, a TV or the Xbox a change arrives when Lamp installs the game again, and the runtime restores the
  last snapshot then, once.

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
mismatched models. Score, pause and menus are plain
and large, over the game (SwiftUI over a SpriteView; HTML over the canvas in a page).

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
