---
name: 3d-game
description: 3D games and scenes in a web page with three.js, on any device that runs web, TVs included - the renderer, models, light and materials, and keeping a scene light enough for a TV, checked on the device. Read before writing or changing 3D in a web page.
---

# 3D in a web page

three.js runs wherever web runs: a Mac, an iPhone or iPad, Android, an Android TV, a Samsung or LG TV and an Xbox.
Any of them can show a 3D game. What differs is speed: a Mac draws far more than a phone, and a TV's chip is often
slower than a phone's. Nothing here limits what you make; it says what costs the most, so you can choose what the
game is worth on the devices it's played on.

For 3D in Swift on Apple's devices (RealityKit), open the scene-3d skill instead. The game skill holds what every game
needs (the frame loop, controls, sound, saves); read it too.

## The renderer

The page loads three.js from `Web/three` through the import map in index.html (`three` and `three/addons/`, the
WebGL build and its addons such as GLTFLoader; nothing is loaded from the network). A game makes one
`THREE.WebGLRenderer({ antialias: true })` and hands it to `game()` in lamp-game.js, which sizes the canvas to
1920x1080, fits it to the screen and runs your `frame`. Read lamp-game.js's comments first.

## Models, light and materials

- Shapes made in code (boxes, spheres, cylinders, extruded outlines), well lit and coloured, often look better than
  mismatched models, and cost little. A model the game needs (a .glb) goes in Web/ and loads once in `init` with
  `new GLTFLoader().loadAsync('ship.glb')`.
- One or two lights computed in the shader are the safe start. MeshStandardMaterial looks good under them;
  MeshLambertMaterial or MeshBasicMaterial cost less.
- Make every mesh, material and texture once in `init` and reuse it; many copies of one shape are one
  `THREE.InstancedMesh`.

## What costs the most

Roughly in order: shadow maps (each light that casts one draws the scene again), full-screen effects
(post-processing, bloom), many lights, a high pixel ratio (lamp-game.js already draws at 1, never at the screen's own),
many draw calls (each distinct mesh and material), large textures, and many triangles.

## On a TV

A TV's browser runs three.js, but often slowly: a scene that's smooth on a Mac can draw a few frames a second on a TV.
Some Samsung models lack WebGL 2. When the game is played on a TV, a light scene keeps it playable:

- few lights and no live shadows (a dark blob under things reads as a shadow);
- no post-processing;
- few draw calls: merge what doesn't move, instance what repeats;
- textures 1024 px at most, and few of them;
- a simple sky (a gradient or a colour) rather than an environment map.

These are suggestions, not limits: a scene that runs well on the person's TV is right, however much it draws. The way
to know is to try it on the device: the log says every ten seconds how its frames kept to time ("frames … ms on
average, slowest … ms"). When frames are late, draw less there, and keep what runs well elsewhere as it is: never make
the game plainer on every device for one slow one unless the person wants the same look everywhere.

## Checking it

`look_at_app` draws the preview on this Mac, which can't show a device's speed; its stats count draws and triangles a
frame, to compare with the budget in the request's device line. `look_at_app` with `on_device` opens the game where
Try On points and shows its log, with the real frame times.
