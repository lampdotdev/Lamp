// What's slow to build and rarely changes: the scene, its camera, and later the level, the ground and the buildings.
// build() puts it all in `built`, so a change to this file builds the world again in the running game, with the player
// and everything else kept (the end of this file; lamp-game.js, "Changes while it's played").
import * as THREE from 'three';
import { hot } from './lamp-game.js';

const live = hot(import.meta);
const worlds = (live.data.worlds ??= new Set());

export class World {
    constructor() {
        this.scene = new THREE.Scene();
        this.camera = new THREE.PerspectiveCamera(60, 16 / 9, 0.1, 10);
        this.built = new THREE.Group();
        this.scene.add(this.built);
        this.build();
        worlds.add(this);
    }

    build() {
        this.scene.background = new THREE.Color(0x1d2a44);
    }

    rebuild() {
        this.built.traverse(o => {
            if (o.geometry) o.geometry.dispose();
            for (const m of [o.material].flat()) if (m) m.dispose();
        });
        this.built.clear();
        this.build();
    }
}

live.accept(() => { for (const world of worlds) world.rebuild(); });
