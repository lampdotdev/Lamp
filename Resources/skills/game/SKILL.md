---
name: game
description: Games, 2D or 3D, made either way - the frame loop, controls (a controller, keys, touch, a TV remote), sound, saves, keeping every frame smooth and light rendering - with the tools for each (Lamp's game runtime in a web page, a Samsung or LG TV app's page for a game played with phones, SpriteKit and Lamp's blocks in Swift, an integration's own), and turning an app into a game. Read before writing or changing a game.
---

# Games

A game is something played in real time, rather than used. What follows holds for every game, whichever way it's
made; each part then names the tools for each make. For a game in 3D, open the 3d-game skill too (or scene-3d for
RealityKit in Swift).

The tools Lamp has for games:

- **Web**: Lamp's game runtime, `Web/lamp-game.js`, with three.js, in a game `make_app_for` made with `kind` "game".
  It's the same on every device that runs web. Read lamp-game.js first, all of it: its comments are the whole
  interface. Below, "Web" means this runtime.
- **A game played with phones on a Samsung or LG TV**: for now a TV app's page (`kind` "app", the phone-controllers
  skill), since the runtime has no `Lamp.controllers` yet. It has no lamp-game.js and no three.js: it follows the TV
  rules and lamp.js instead. Its frame loop is its own `requestAnimationFrame`, moving everything by the time since the
  last frame; players are `Lamp.controllers` (and the remote's keys, with `Lamp.navigation = false`); sound is Web
  Audio and saves are `LampStore`, as the TV rules say; and it's drawn in 2D on a canvas. The rest of this skill holds
  for it wherever it doesn't name the runtime.
- **Native Apple** (Mac, iPhone, iPad, Apple TV): SpriteKit for 2D, SwiftUI for menus and scores, and Lamp's blocks
  in LampSupport.swift. For 3D, LampSceneView (the scene-3d skill) is for Mac-only apps; a native 3D game on iPhone,
  iPad or Apple TV writes its own 3D with that device's frameworks (RealityKit or SceneKit), without LampSceneView.
- **Native Android**: Lamp has no game help in Kotlin yet: write the game's own frame loop on a SurfaceView or a
  Canvas, and its controls, sound and saves with Android's own APIs.
- **An integration's device** (Roku…): what its integration declares; read the device-integrations skill.
- **Apple Watch**: Lamp has no game help there.

## The frame loop

Everything that moves is moved by the time since the last frame, never by a fixed step per frame: devices draw at
different rates, and a slow frame must not slow the game.

- Web (the runtime): `game({ renderer, init, frame })` from lamp-game.js; move by `f.dt`. Never requestAnimationFrame, timers, the
  clock, Math.random or localStorage: `random()`, `save()` and `load()` from the runtime let Lamp's preview replay a
  play exactly.
- SpriteKit: in a SpriteView, one SKScene subclass for each screen with `scaleMode = .resizeFill`; movement in
  `update(_:)` scaled by the time since the last frame; collisions with SKPhysicsBody, its category and contact masks,
  and an SKPhysicsContactDelegate. An SKCameraNode follows the player through a world bigger than the screen.

## Controls

Controls follow the input the player has, not the device: the same player may pick up an Xbox, PlayStation or
Switch controller, the keyboard or the touch screen, and switch while playing.

- **Web**: lamp-game.js reads all of them as one pad, `f.pads[0]`. Write the controls once, as actions mapped to the
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

- Web: `sound` in lamp-game.js, effects made in code with `sound.tone` unless the person gave files.
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

## Keeping every frame smooth

A frame has about 16 ms, and anything that runs during play takes from it, so a slow piece is a stutter:

- load each picture, model and sound once and reuse it; prepare a level before it starts;
- reuse what comes and goes (bullets, enemies, particles) rather than making new ones each time;
- allocate nothing per frame, and keep per-frame work to what moves;
- many copies of one thing are one draw (THREE.InstancedMesh, `LampScene.copies` in a Mac-only app).

The request's device line names the slowest device the game is played on and its budget; the log says how frames kept
to time. When frames are late, draw less. On a TV, draw much less: the 3d-game skill says how.

## The look

Sprites, characters and backgrounds are art from `make_art`, all in one style, on a transparent background where they
move. Shapes and colors made in code, well lit, look better than mismatched models. Score, pause and menus are plain
and large, over the game (SwiftUI over a SpriteView; HTML over the canvas in a page).

After changing anything that moves, look_at_app with `motion` shows what changes frame to frame and catches flicker a
single picture hides. Play it the way the person would before you finish: a game that only looks right isn't done.

## A game and the wish's other apps

When the person wants an app to become a game ("actually, make it a game"), change its code in place: the same app,
now played. If they might want both (the app they use and a game beside it), ask once whether to keep the app as well
or replace it. Turning it into a game is a change to that app: `make_app_for` with its folder in `app` and `kind`
"game" (made native first, as the web-or-native skill says), keeping its folder and data, and its code changed into a
game. A game played with phones on a Samsung or LG TV is the exception for now: it stays `kind` "app", on its TV
app's page (above). A game beside
the app is one more app, only when they say they want both and the game is of another kind than the app:
`make_app_for` with `another` and `kind` "game", in a folder of its own, once they chose that when you asked. Two apps
of one kind can't be in one wish yet (the `more-apps` skill), and a game is never made web only to get around that. A
game that becomes an app again is the same in reverse.
