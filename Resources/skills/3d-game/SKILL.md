---
name: 3d-game
description: 3D games and scenes in a web page with three.js, on any device that runs web, TVs included - the renderer, models, light and materials, and keeping a scene light enough for a TV, checked on the device. Read before writing or changing 3D in a web page.
---

# 3D in a web page

three.js runs in a page wherever the device takes a page (`make_app_for`'s table) and its browser gives WebGL 2: a
host for the page isn't enough on its own, so check WebGL 2 first (below). What differs then is speed: a Mac draws far
more than a phone, and a TV's chip is often slower than a phone's. Nothing here limits what you make; it says what
costs the most, so you can choose what the game is worth on the devices it's played on.

For 3D in Swift in a Mac-only app (RealityKit through LampSceneView), open the scene-3d skill instead; native 3D on
iPhone, iPad or Apple TV is written with that device's own frameworks. The game skill holds what every game needs
(the frame loop, controls, sound, saves); read it too.

## The renderer

The page loads three.js from `Web/three` through the import map in index.html (`three` and `three/addons/`, the
WebGL build and its addons such as GLTFLoader; nothing is loaded from the network). A game makes one
`THREE.WebGLRenderer({ antialias: true })` and hands it to `game()` in lamp-game.js, which sizes the canvas to
1920x1080, fits it to the screen and runs your `frame`. Read lamp-game.js's comments first.

The three.js Lamp ships asks the browser only for a WebGL 2 context and stops with an error when it gets none, so
WebGL 2 comes before anything else here: check on the device that a canvas gives one (log whether
`canvas.getContext('webgl2')` returns a context, and read the log with `look_at_app` and `on_device`). Most browsers
have it; not every Samsung TV does. Where it's missing, make the game another way (2D on a canvas, or native on that
device) or tell the person why 3D in a page can't run there.

## Models, light and materials

- Shapes made in code (boxes, spheres, cylinders, extruded outlines), well lit and colored, often look better than
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

A TV's browser with WebGL 2 runs three.js, but often slowly: a scene that's smooth on a Mac can draw a few frames a
second on a TV. Once the renderer runs there, a light scene keeps the game playable:

- few lights and no live shadows (a dark blob under things reads as a shadow);
- no post-processing;
- few draw calls: merge what doesn't move, instance what repeats;
- textures 1024 px at most, and few of them;
- a simple sky (a gradient or a color) rather than an environment map.

These are suggestions, not limits: a scene that runs well on the person's TV is right, however much it draws. The way
to know is to try it on the device: the log says every ten seconds how its frames kept to time ("frames … ms on
average, slowest … ms"). When frames are late, draw less there, and keep what runs well elsewhere as it is: never make
the game plainer on every device for one slow one unless the person wants the same look everywhere.

## Checking it

`look_at_app` draws the preview on this Mac, which can't show a device's speed; its stats count draws and triangles a
frame, to compare with the budget in the request's device line. `look_at_app` with `on_device` opens the game where
Try On points and shows its log, with the real frame times.
