---
name: web-game
description: The short guide to a new web game at home on the Mac, on Lamp's game runtime - the runtime's contract, the stage in the window, screens over the canvas, keeping the player's place, how it looks, and what's checked when. Lamp hands it over with make_app_for, with game-feel and the skills the call's `needs` named; for this game they stand in for the game, game-ui, 2d-game and 3d-game skills, which serve games elsewhere.
---

# A new web game on the Mac

This guide holds how the game runs on Lamp's runtime; game-feel, handed with it, holds what makes it good to play. Both are for every game, and with the skills `needs` named they're what you write it from: don't open the game, game-ui, 2d-game or 3d-game skills, or read Web/lamp-game.js or Web/lamp-phaser.js in full: grep them for one export when you need it. In 2D the game is Phaser 3.90 scenes through `phaser()`. In 3D, game-3d says how it draws; the rest here holds. Write the first files together in one message, then finish: Lamp builds the game and opens it when your turn ends.

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

Changes go into the running game, and these rules keep the player's place through every one; game-live is for a change that moves the game's structure. Everything that says where the game is goes in the one `state` object, plain data: change its fields, never replace it. `create` reads it and builds that place, with no title over a game under way. HUD and menus are found at each start, never at a module's top level, and `busy()` is true while a round is on.

## How it looks

Decide before drawing: its world, one material its screens are made of, four to eight colors, one signature motion. Compose each screen for this game, not a centered stack of pills, emoji art or soft cards on a gradient. Every action answers at once in sight and sound, each with a short effect from the `assets` tool. The finished look in game-feel is the bar every screen meets. The HTML above shows how screens layer over the canvas and follow the state, not a finished design: style it for this game, keeping the fixed stage and the black around it.

## What's checked, and when

Lamp checks the game itself: its code parses, it builds, and it opens without crashing. A failure there comes back to you to fix, as another step. Lamp also tells the person whether its window drew. So write the change and finish, with no `look_at_app` or `use_app`, and nothing in the shell that plays, screenshots or runs the game in its place. Your last reply says in a sentence what you made; whether it's open and drew is Lamp's to say, after your reply, so never say it's built, open, working or tested.

When the person asks you to play it, test it, check it or judge how it looks, open the game-playtest skill and do only what they asked. One such request doesn't reach the changes after it.

## More, when the game calls for it

What a game needs beyond this and game-feel follows from its mechanics and how it's drawn, not from the words of the request. The skills `make_app_for`'s `needs` named came with this guide; one the game turns out to need, now or in a later request, open with `read_skill` then. Most games need none.

- **game-3d**: it's drawn in 3D, a world with depth and a camera in it.
- **game-physics**: things move as bodies, falling, rolling, stacking, tilting, bouncing off each other. Steering, simple gravity and what touches what don't need it.
- **game-levels**: more than one level or stage, unlocks and a level select, a menu that's a place.
- **game-art**: the person asked for a look, or the game is mostly its look.
- **2d-game**: tilemaps, a scrolling world, sprite-sheet animation.
- **game-live**, never in `needs`: open it when a change to the open game moves its structure (new or split modules, a world that streams, what has to last renamed or moved) or won't go in. A color, a number or text needs only the rules above.
- **assets**: choosing between packs.
