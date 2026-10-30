// {{NAME}}: not made yet. The same card a new app shows (a hammer, its name, "Lamp is making this game.") on the
// game's background, so the window is plainly Lamp waiting rather than a game that looks broken. The game replaces
// all of it, keeping its shape: this file only puts the parts together, world.js builds the world (and builds it
// again in place when it changes), and each part that changes as the game is played is a class in a module of its own
// that takes its changes while the game runs (making.js; lamp-game.js, "Changes while it's played"). Everything that
// has to last through a change is registered here by name: the renderer, the camera, the gameplay state and the
// world's parts, so a change that can't be swapped in runs this file again with all of them where they were
// (lamp-game.js, "What the game registers").
import * as THREE from 'three';
import { game, hot } from './lamp-game.js';
import { World } from './world.js';
import { Making } from './making.js';

const live = hot(import.meta);
const renderer = live.renderer(() => new THREE.WebGLRenderer({ antialias: true }));
const camera = live.camera('main', () => new THREE.PerspectiveCamera(60, 16 / 9, 0.1, 10));
// Everything that says where the game is goes in here. Raise `version` when a field changes its meaning.
const play = live.state('play', { version: 1, start: () => ({ mode: 'making', time: 0 }) });
const world = live.keep('world', () => new World());
const making = new Making(document.title);

game({
    renderer,
    frame(f) {
        play.time += f.dt;
        making.update(f.dt);
        renderer.render(world.scene, camera);
    },
});
