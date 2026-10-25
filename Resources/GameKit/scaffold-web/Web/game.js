// {{NAME}}: the game. A lit floor and a ball the left stick rolls, with a camera behind it that the right stick
// turns, and its name in the corner.
import * as THREE from 'three';
import { game } from './lamp-game.js';

const renderer = new THREE.WebGLRenderer({ antialias: true });
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x1d2a44);
const camera = new THREE.PerspectiveCamera(60, 16 / 9, 0.1, 200);

const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 40, 40, 40),
    new THREE.MeshStandardMaterial({ color: 0x8a97a8, roughness: 0.9 }));
floor.rotation.x = -Math.PI / 2;
const ball = new THREE.Mesh(new THREE.SphereGeometry(0.5, 32, 16),
    new THREE.MeshStandardMaterial({ color: 0xe07020, roughness: 0.4 }));
ball.position.y = 0.5;
const sun = new THREE.DirectionalLight(0xffffff, 2.2);
sun.position.set(4, 8, 3);
scene.add(floor, ball, sun, new THREE.HemisphereLight(0xbfd4ff, 0x404040, 0.8));

const label = document.createElement('div');
label.textContent = '{{NAME}}';
label.style.cssText = 'position:fixed;left:24px;top:20px;color:#fff;font:600 28px -apple-system,system-ui,sans-serif;z-index:5';
document.body.append(label);

let yaw = 0;
game({
    renderer,
    frame(f) {
        const pad = f.pads[0];
        yaw -= pad.rx * 2 * f.dt;
        const forward = new THREE.Vector3(-Math.sin(yaw), 0, -Math.cos(yaw)), right = new THREE.Vector3(Math.cos(yaw), 0, -Math.sin(yaw));
        ball.position.addScaledVector(forward, pad.ly * 4 * f.dt).addScaledVector(right, pad.lx * 4 * f.dt);
        camera.position.copy(ball.position).addScaledVector(forward, -6).setY(3);
        camera.lookAt(ball.position);
        renderer.render(scene, camera);
    },
});
