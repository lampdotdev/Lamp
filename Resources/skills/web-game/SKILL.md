---
name: web-game
description: The short guide to a new web game at home on the Mac, on Lamp's game runtime - the runtime's contract, the stage in the window, screens over the canvas, keeping the player's place, how it looks, and the checks. Lamp hands it over with make_app_for; it stands in for reading the game, 2d-game and game-ui skills first.
---

# A new web game on the Mac

This guide is enough to write the game. Don't open the game, 2d-game or game-ui skills first, or read Web/lamp-game.js or Web/lamp-phaser.js in full: grep them for one export when you need it. In 2D the game is Phaser 3.90 scenes through `phaser()`. In 3D, open the 3d-game skill for how it draws; the rest here holds. Write the first files together in one message, and look in that message's last call or the next one.

## The runtime's contract

- **Files.** Yours are `Web/index.html` (keep its head: lamp.js, the import map, then game.js as a module), `Web/game.js` and modules beside it; delete the scaffold's world.js and making.js with `delete_file` beside your writes. lamp-game.js, lamp-phaser.js, lamp-controllers.js, lamp.js, phaser/, three/, rapier/ and Sources/ are Lamp's: never edit them.
- **One frame clock.** Phaser's loop is asleep; each of the runtime's frames steps it once. Use a scene's `update(time, delta)` (milliseconds), tweens and Phaser's timers. Never requestAnimationFrame, setTimeout, setInterval, Date, Math.random or localStorage: `random()`, `save(name, value)`, `load(name)`, so the preview replays a play exactly.
- **Input.** `pad()` merges controllers, keys and touch: `lx ly rx ry` -1 to 1 (up positive), buttons as BUTTON bits in `down pressed released`. WASD and the arrows are the left stick, Space or Enter is A. Phaser's keyboard is off: never `addKey`. Name the controls once in CONTROLS; a prompt uses `label()` or `glyph()` inside `onInput(draw)`, never a key's name. Keys the person named: `keyboardHints: { leftStick: 'arrows' }`.
- **Sound.** Phaser's is off. Before writing any, `assets` with `kind` sound and `limit` 30 lists every effect: fetch one for each thing the player does or meets, and use the paths it gives. Load each once with `await sound.load('assets/…')` at the top of game.js and `sound.play(s, { volume })` when things happen; `sound.tone({…})` only for what nothing there fits.
- **Local files.** Nothing comes from the network. Pictures load in `preload`, or are drawn once with `this.make.graphics({ add: false })` and `generateTexture`.

## The stage and the window

The 1920x1080 stage is fitted to the window with black around it, from 480x270 up. Lay everything out in stage units, with the player, HUD and every control inside it, 96 px in from the sides and 54 from top and bottom. Nothing scrolls or zooms, and nothing listens for resize. HTML sizes itself from the stage as `#ui` below does, never in fixed CSS pixels.

## Screens over the canvas

The canvas is `position: fixed`, so anything without a stacking order of its own lies under it. Title, HUD and results live in one `#ui` box over the stage, above the canvas, passing clicks through except on buttons. Lamp's own layers start at z-index 10.

```html
<style>
#ui { position: fixed; left: 50%; top: 50%; transform: translate(-50%, -50%); width: min(100vw, 177.78vh); aspect-ratio: 16 / 9;
      z-index: 5; overflow: hidden; pointer-events: none; font-size: calc(min(100vw, 177.78vh) / 64); color: #fff; }
#ui button { pointer-events: auto; font: inherit; }
.hidden { display: none; }
</style>
<div id="ui"><div id="title"><h1>…</h1><button id="play">Play</button></div>
<div id="hud" class="hidden">…</div><div id="results" class="hidden">…<button id="again">Play Again</button></div></div>
```

```js
import * as Phaser from 'phaser';
import { phaser, pad } from './lamp-phaser.js';
import { BUTTON, STICK, sound, random, save, load, label, onInput, hot } from './lamp-game.js';

const CONTROLS = { move: STICK.LEFT, start: BUTTON.A, pause: BUTTON.MENU };
const play = hot(import.meta).state('play', { version: 1, start: () => ({ mode: 'title', score: 0, left: 30, x: 960 }) });
const catchSound = await sound.load('assets/pack/coin.wav');   // the page path `assets` gave
const el = id => document.getElementById(id);

class Main extends Phaser.Scene {
    constructor() { super('main'); }
    create() {                                     // the one start: it reads the state and shows that screen
        this.ship = this.physics.add.sprite(play.x, 940, 'ship').setCollideWorldBounds(true);
        el('play').onclick = el('again').onclick = () => this.begin();
        this.show();
    }
    begin() { Object.assign(play, { mode: 'play', score: 0, left: 30 }); this.show(); }
    end() { play.mode = 'over'; save('best', Math.max(load('best') ?? 0, play.score)); this.show(); }
    show() { for (const [id, mode] of [['title', 'title'], ['hud', 'play'], ['results', 'over']]) el(id).classList.toggle('hidden', play.mode !== mode); }
    update(time, delta) {
        const p = pad(), dt = delta / 1000;
        if (play.mode !== 'play') { if (p.pressed & CONTROLS.start) this.begin(); this.ship.setVelocityX(0); return; }
        this.ship.setVelocityX(p.lx * 900); play.x = this.ship.x;
        if ((play.left -= dt) <= 0) this.end();
    }
}
phaser({ scenes: [Main], physics: { default: 'arcade' }, busy: () => play.mode === 'play' });
```

## The flow

Title, play, results, unless the request plainly suits another opening; keep it in a `Flow:` line in APP.md. The title has the name and one big Play; a click or A starts it, and it names no key or control: those come after the press, briefly, as the round begins. The HUD stays large through play. Results say what happened first, then Play Again, which goes straight into a round. Play and Play Again are really in view and clickable.

## Keeping the player's place

Changes go into the running game. Everything that says where the game is goes in the one `state` object, plain data: change its fields, never replace it. `create` reads it and builds that place, with no title over a game under way. HUD and menus are found at each start, never at a module's top level, and `busy()` is true while a round is on.

## How it looks

Decide before drawing: its world, one material its screens are made of, four to eight colors, one signature motion. Compose each screen for this game, not a centered stack of pills, emoji art or soft cards on a gradient. Every action answers at once in sight and sound, each with a short effect from the `assets` tool.

## Checks

The first `look_at_app` shows the draft in the game's window and plays it from the start in the hidden preview: the person is watching, so go on working. Every check below runs before you say it's done; none is optional, however good the draft looks.

1. One `use_app` plays a whole round as the person would: **start**, **steer** both ways, take a **hit** (steer into one, watching the score), **finish** (wait out the round to the results), press A to **restart** into a new round.
2. One `look_at_app` with `shape` "960x540" plays the **opening** and the first seconds of play in a **smaller window**: the player, HUD and Play show, nothing is cut off or under the canvas.

No key name on the opening. Fix what fails and run that check again, with `reopen` for the opening at full size. Say what you didn't run.

## More

Open a skill only when the game needs it: **game** ("Changes while it's played": modules that swap in, big worlds; phones as players), **2d-game** (tilemaps, sprite sheets, physics, pixel art, cameras), **game-ui** (other flows, menus that are places), **assets** (choosing packs).
