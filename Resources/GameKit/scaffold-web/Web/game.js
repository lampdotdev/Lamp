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
making.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"'
    + ' stroke-linejoin="round"><path d="m15 12-8.373 8.373a1 1 0 1 1-3-3L12 9"/><path d="m18 15 4-4"/>'
    + '<path d="m21.5 11.5-1.914-1.914A2 2 0 0 1 19 8.172V7l-2.26-2.26a6 6 0 0 0-4.202-1.756L9 2.96l.92.82A6.18 6.18 0 0 1'
    + ' 12 8.4V10l2 2h1.172a2 2 0 0 1 1.414.586L18.5 14.5"/></svg>'   // Lucide's hammer (ISC, see NOTICE.md)
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
