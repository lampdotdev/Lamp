// {{NAME}}: not made yet. The same card a new app shows (a hammer, its name, "Lamp is making this game.") on the
// game's background, so the window is plainly Lamp waiting rather than a game that looks broken. The game replaces
// all of it, keeping its shape: this file only puts the parts together, world.js builds the world (and builds it
// again in place when it changes), and each part that changes as the game is played is a class in a module of its own
// that takes its changes while the game runs (making.js; lamp-game.js, "Changes while it's played").
import * as THREE from 'three';
import { game } from './lamp-game.js';
import { World } from './world.js';
import { Making } from './making.js';

const renderer = new THREE.WebGLRenderer({ antialias: true });
const world = new World();
const making = new Making(document.title);

game({
    renderer,
    frame(f) {
        making.update(f.dt);
        renderer.render(world.scene, world.camera);
    },
});
