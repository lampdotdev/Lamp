// {{NAME}}: not made yet. An empty stage drawn as a wireframe, with outlines of a few shapes rising from its grid
// and the camera slowly going round, under "Lamp is making this game.", so the window shows what's coming rather
// than a game that looks broken. The game replaces all of it.
import * as THREE from 'three';
import { game } from './lamp-game.js';

const renderer = new THREE.WebGLRenderer({ antialias: true });
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0d1730);
scene.fog = new THREE.Fog(0x0d1730, 14, 42);
const camera = new THREE.PerspectiveCamera(50, 16 / 9, 0.1, 200);

const line = (color, opacity) => new THREE.LineBasicMaterial({ color, transparent: true, opacity, fog: true });

// The floor: a fine grid under a coarse one, both fading into the distance.
const fine = new THREE.GridHelper(60, 120, 0x3fa9ff, 0x3fa9ff);
fine.material = line(0x3fa9ff, 0.12);
const coarse = new THREE.GridHelper(60, 12, 0x6cc6ff, 0x6cc6ff);
coarse.material = line(0x6cc6ff, 0.35);
coarse.position.y = 0.002;
scene.add(fine, coarse);

// Placeholders: the outlines of what a world is made of, in a ring round the middle (where the words are), each
// rising out of the floor in turn.
const shapes = [
    new THREE.BoxGeometry(2.2, 1.6, 1.8),
    new THREE.BoxGeometry(1.2, 3, 1.2),
    new THREE.CylinderGeometry(0.7, 0.7, 2.4, 16),
    new THREE.ConeGeometry(0.8, 2, 8),
    new THREE.SphereGeometry(0.7, 12, 8),
    new THREE.BoxGeometry(1, 0.8, 3.2),
    new THREE.ConeGeometry(0.6, 1.6, 6),
].map((geometry, i, all) => {
    geometry.computeBoundingBox();
    geometry.translate(0, -geometry.boundingBox.min.y, 0);   // standing on the floor, so it grows upwards
    const outline = new THREE.LineSegments(new THREE.EdgesGeometry(geometry), line(0x9fe0ff, 0.9));
    const around = (i / all.length) * Math.PI * 2;
    outline.position.set(Math.sin(around) * 6.5, 0, Math.cos(around) * 6.5);
    outline.rotation.y = around;
    scene.add(outline);
    return { outline, delay: 0.5 + i * 0.4 };
});

// What the window says while the game is made.
const style = document.createElement('style');
style.textContent = `
  .lamp-making { position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center;
    justify-content: center; gap: 10px; pointer-events: none; z-index: 5; color: #e8f4ff;
    font-family: -apple-system, system-ui, sans-serif; text-shadow: 0 2px 12px rgba(0, 0, 0, 0.5); }
  .lamp-making h1 { margin: 0; font-size: 44px; font-weight: 700; letter-spacing: -0.5px; }
  .lamp-making p { margin: 0; font-size: 18px; opacity: 0.8; }
  .lamp-making .bar { width: 160px; height: 3px; margin-top: 8px; border-radius: 2px; overflow: hidden;
    background: rgba(159, 224, 255, 0.18); }
  .lamp-making .bar::after { content: ''; display: block; width: 40%; height: 100%; border-radius: 2px;
    background: #9fe0ff; animation: lamp-making 1.6s ease-in-out infinite; }
  @keyframes lamp-making { from { transform: translateX(-100%); } to { transform: translateX(250%); } }
  @media (prefers-reduced-motion: reduce) { .lamp-making .bar::after { animation: none; width: 100%; } }`;
const making = document.createElement('div');
making.className = 'lamp-making';
making.innerHTML = '<h1></h1><p>Lamp is making this game.</p><div class="bar"></div>';
making.querySelector('h1').textContent = '{{NAME}}';
document.head.append(style);
document.body.append(making);

// With Reduce Motion on, the stage stands still: shapes already up, no pulse, the camera where it starts. Asked every
// frame, so turning it on while the game is made takes effect at once.
const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
const ease = (t) => 1 - Math.pow(1 - Math.min(Math.max(t, 0), 1), 3);
let time = 0;
game({
    renderer,
    frame(f) {
        const still = reduced.matches;
        if (!still) time += f.dt;
        for (const { outline, delay } of shapes) {
            const grown = still ? 1 : ease((time - delay) / 1.2);
            const pulse = still ? 0.9 : 0.8 + 0.2 * Math.sin(time * 2 + delay * 3);
            outline.scale.set(1, Math.max(grown, 0.001), 1);
            outline.material.opacity = 0.25 + 0.65 * grown * pulse;
        }
        const angle = time * 0.12;
        camera.position.set(Math.sin(angle) * 15, 7, Math.cos(angle) * 15);
        camera.lookAt(0, 0.5, 0);
        renderer.render(scene, camera);
    },
});
