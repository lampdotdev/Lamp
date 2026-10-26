// {{NAME}}: not made yet. The same card a new app shows (a hammer, its name, "Lamp is making this game.") on the
// game's background, so the window is plainly Lamp waiting rather than a game that looks broken. The game replaces
// all of it.
import * as THREE from 'three';
import { game } from './lamp-game.js';

const renderer = new THREE.WebGLRenderer({ antialias: true });
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x1d2a44);
const camera = new THREE.PerspectiveCamera(60, 16 / 9, 0.1, 10);

const style = document.createElement('style');
style.textContent = `
  .lamp-making { position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center;
    justify-content: center; gap: 12px; pointer-events: none; z-index: 5; color: #fff;
    font-family: -apple-system, system-ui, sans-serif; }
  .lamp-making svg { width: 64px; height: 64px; color: rgba(255, 255, 255, 0.55); }
  .lamp-making h1 { margin: 0; font-size: 34px; font-weight: 700; }
  .lamp-making p { margin: 0; font-size: 20px; color: rgba(255, 255, 255, 0.55); }`;
const making = document.createElement('div');
making.className = 'lamp-making';
making.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round">'
    + '<g transform="rotate(40 12 12)"><rect x="10.8" y="8.5" width="2.4" height="13" rx="1.2"/>'
    + '<path d="M7 3.5h8.5l2.5 2.2v2.8H7z"/></g></svg>'
    + '<h1></h1><p>Lamp is making this game.</p>';
making.querySelector('h1').textContent = '{{NAME}}';
document.head.append(style);
document.body.append(making);

game({
    renderer,
    frame() {
        renderer.render(scene, camera);
    },
});
