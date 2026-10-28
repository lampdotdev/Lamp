Kind: game, drawn with three.js (Lamp's runtime in Web/lamp-game.js), at home on the Mac; played together on one
screen with phones (the page in Phone/) and controllers.
Look: a painted battlefield seen from above at an angle (each map's terrain is a painting draped over its 3D ground),
low-poly drones, tanks, robot squads and Goliath walkers in each side's color, glowing tracers and explosions; a
night-blue glass HUD with rounded cards: scrap and the clock at the top, the minimap and build cards on the right,
squad chips and Select army at the bottom.

# Battle Drones

Battle Drones by Simon Willison (Apache License 2.0, `Web/LICENSE-battledrones`), a real-time strategy game in the
spirit of Command & Conquer: two to four armies of flying and ground drones mine scrap, build bases and fight for the
map until one side's HQ and every Goliath are gone. Seven hand-made maps (one for four players) and endless generated
ones in five biomes, Last Stand (waves), Ops (short missions with three stars each), a Daily Op, mutators that change
the rules, openers, commander calldowns (Barrage, EMP, Drop Pod, the Sky Hammer), Uplinks and supply drops, veteran
units, a career with ranks and medals, an announcer, adaptive music and sound, all synthesized.

The upstream game's online duels, sound-modem duels and battles between AI models over the network aren't here:
people play together on one screen instead, which works with no server and no account.

## Playing

- **One player** on the Mac: the menu's ▶ Play against the computer (Easy, Normal, Hard), or 🤖 Watch AI vs AI.
  - Mouse: click a unit to select it, Shift-click to add one, drag a box round several, click the map to order them
    there (attack-moves), right-click to order without changing the selection, scroll to zoom.
  - Keyboard: W A S D or the arrows move the camera, + and - zoom, Q selects the whole army, 1 2 3 the squads, U
    unloads Condors, G anchors or packs up a Goliath, Delete sells a building, . changes the game's speed, J jumps to
    the last alert, C the cinematic camera when watching, P or Space pauses, Esc cancels.
  - A touch screen: tap, drag a box, two fingers to move and pinch to zoom.
  - A controller (`js/lamp/pads.js`): in the menus the stick or d-pad moves a highlight and A presses; in a match the
    left stick moves a pointer that does what the mouse does (A clicks, held it drags a box, RT orders), the right
    stick or the pointer at an edge moves the camera, LB and RB zoom, X the whole army, Y the last alert, B cancels,
    Menu pauses, View the speed, the d-pad's left, up and right the squads. Its legend names each button as the
    player's own controller does (`glyph()` from lamp-game.js), from `CONTROLS` in pads.js: a new control goes there.
- **Together** (📱 Play together on the menu, `js/lamp/party.js`): one screen shows the whole battle, its camera
  following the action, and each person commands a side:
  - from a phone, by scanning the lobby's QR code (Lamp serves Phone/ to phones on the same Wi-Fi while the game is
    open, and carries what they send with `Lamp.controllers`; a phone keeps its name and side across a reload);
  - with a controller (A in the lobby takes a seat, B gives it up, Menu starts) or the mouse (🖱️ Sit here): their
    table is drawn in a corner of the screen.
  - Sides nobody takes go to the computer. Each seat has the game's own `Controller` for its side
    (`game/controller.js`), so a tap means what it means in single player.
  - The phone's table (`Phone/phone.js`): the battlefield as the side sees it (a tap selects or orders, a drag boxes
    units, holding shows the spot on the screen), Army, Idle, Miners, Stop and Clear, and the Build, Train and
    Calldowns tabs. A building bought from a phone or a corner table is put down where it fits best once it's built
    (`Seat.drain`).
  - A corner table: the left stick moves a cursor on its map, A selects or orders (held, a box), X the army, Y shows
    the spot on the screen, LB and RB go through the shop, RT buys, B clears.

## Code

The page is `Web/`: `index.html`, `css/style.css` (the game's look) and `css/lamp.css` (the controller's pointer, the
lobby and the corner tables), and `js/`, ES modules with no build step, from the upstream TypeScript (types taken out,
its comments kept). Lamp's files beside them (`lamp-game.js`, `lamp.js`, `lamp-device.js`, `lamp-controllers.js`,
`three/`) are written by Lamp; don't edit them.

- `js/main.js`: the menu, the match's start, and `game({ renderer, fill: true, touch: false, keyboard: false, init,
  frame, snapshot, busy })`: Lamp's runtime calls `frame` about 60 times a second, which runs the controllers, the
  seats and the match. `fill` because the page lays itself out at the window's size, its HUD being HTML.
- `js/sim/`: the game itself, with no drawing: the world (`types.js`, `world.js`), the rules and numbers
  (`balance.js`: every unit's and building's cost, health, speed and weapons), economy, combat, movement, fog,
  maps (`maps.js`, the hand-made ones; `mapgen.js`, the generated ones), mutators (`rules.js`), openers, powers,
  Uplinks and crates (`objectives.js`), Goliaths, infantry, Last Stand (`modes/survival.js`), Ops (`ops.js`) and the
  computer's commanders (`ai/`). It's deterministic: the same commands give the same match.
- `js/game/`: the match on screen: `GameScene.js` (the match: its commanders and seats, each tick, the camera,
  input, the finale, `snapshot()`), `controller.js` (what a tap means: select, order, build, board, drop),
  `three/` (the 3D view: `stage.js` the renderer and light, `terrain.js`, `models.js` the units and buildings built
  in code, `materials.js`), `render/` (units, effects, wrecks, calldowns), `audio.js`, `music.js`, `voices.js` and
  `announcer.js` (all synthesized), `career.js`, `daily.js`, `mode.js` (the menu's choices).
- `js/ui/`: the HUD (`hud.js`, the build cards and minimap; `report.js`, the after-action report), the menu's
  career and Ops sheets, the pause menu.
- `js/lamp/`: what makes it a Lamp game: `pads.js` (controllers), `party.js` (playing together, with the phones),
  `snapshot.js` (a match as JSON).
- `js/lib/qrcode.js`: qrcode-generator by Kazuhiko Arase (MIT, `Web/LICENSE-qrcode-generator`), for the lobby's code.
- `Phone/`: the phone's page (`index.html`, `phone.js`, `phone.css`), loading `lamp-controller.js`, which Lamp
  serves beside it. It talks only to the game: what it sends is in phone.js's comment and party.js's `onMessage`.

## Data

Everything ships with the game; nothing is fetched while it plays and there's no key or account. `Web/assets/`: each
map's painted terrain in chunks (`maps/<id>/t_<col>_<row>.webp`, with its `thumb.webp` and `meta.json`), unit and
building icons for each side (`icons/`), rock textures for each biome and the menu's key art. The career, the
settings, Last Stand records and the random maps seen are kept with `localStorage` (keys starting `battledrones.`).

## Worked examples

**A change while a match is played.** `busy()` is true while a match is under way and not paused, so a change of code
waits for a pause (P, Space, Menu), the end, or the person's Reload; then the page opens again with the new code and
carries on: `snapshot()` in main.js gives the world and every commander's plans as JSON (`GameScene.snapshot`,
`js/lamp/snapshot.js`, which keeps the sim's Maps, Sets and typed arrays), the clock, the camera, the menu's choices
and a match played together's seats, about 100 to 200 KB for a long four-side match. `init` reads it with
`pendingRestore()` and starts the match from it (`resume` in main.js, `GameScene`'s `resume`), so the same battle
plays on exactly as it would have, without the menu first. Phones rejoin by themselves and find their sides by the id
each keeps. What isn't kept: the effects in the air and the replay record of the match so far.

**Keeping it fast where it's slowest.** The slowest place it can go is an Xbox One in Developer Mode, whose budget is
about 200 draws and 300,000 triangles a frame, with no shadow maps. Lamp's preview counts both for a play, and the
runtime logs the frame rate every ten seconds wherever it's played. The game already steps down by itself when frames
come slow (`Stage.adapt` and `degrade` in `three/stage.js`: pixels above 1x, then the shadow map's size, then shadows,
then pixels again), so look at a four-side match in the preview and read its draws: units and buildings are built in
code (`three/models.js`) and drawn per entity, so the draws grow with the armies. To fit an Xbox One, start without
shadows when it's one of the places (`setShadows(false)` in Stage's constructor), draw the effects' particles from one
mesh (`three/particles.js` already does), and draw many units of one kind as one `InstancedMesh`.

## Easy to change

- What units and buildings cost, how strong and fast they are: `UNITS` and `BUILDINGS` in `sim/balance.js`.
- How each looks: `three/models.js` (shapes and colors in code) and `side-style.js` (the sides' colors).
- The maps: `sim/maps.js`; the light, sky and fog of each biome: `LOOKS` in `three/stage.js`.
- The rules a match can be played with: `MUTATORS` in `sim/rules.js`; the commanders' personalities: `sim/ai/`.
- The menu: `showMenu` in `main.js` and `css/style.css`; the lobby and corner tables: `party.js` and `css/lamp.css`.
- The phone's table: `Phone/`.
