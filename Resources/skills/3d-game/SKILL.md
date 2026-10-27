---
name: 3d-game
description: 3D games and scenes in a web page with three.js, on any device that runs web, TVs included - the renderer, models, light and materials, and what costs the most. Read before writing or changing 3D in a web page.
---

# 3D in a web page

three.js runs in a page wherever the device takes a page (`make_app_for`'s table) and its browser gives WebGL 2: a
host for the page isn't enough on its own, so check WebGL 2 first (below). What differs then is speed: a Mac draws far
more than a phone, and a TV's chip is often slower than a phone's. Nothing here limits what you make; it says what
costs the most, so you can choose what the game is worth on the devices it's played on.

Lamp ships three.js in two pages: a game's page on its runtime (`make_app_for` with `kind` "game"), and a Samsung or LG
TV app's page, which is what a game played with phones is for now (the phone-controllers skill). The TV app's page has
no game runtime: the TV rules say how it loads three.js, and it makes its own renderer and frame loop.

A 3D game is made this way by default, on every device Lamp has a host for a page on, the Mac included. 3D in Swift,
in a Mac app made natively (because the person asked for native, or the app was made so), is the scene-3d skill's
(RealityKit through LampSceneView); native 3D on iPhone, iPad or Apple TV is written with that device's own
frameworks. The game skill holds what every game needs
(the frame loop, controls, sound, saves); read it too.

## The renderer

The page loads three.js from `Web/three` through the import map in index.html (`three` and `three/addons/`, the
WebGL build and its addons such as GLTFLoader; nothing is loaded from the network). A game on the runtime makes one
`THREE.WebGLRenderer({ antialias: true })` and hands it to `game()` in lamp-game.js, which sizes the canvas to
1920x1080, fits it to the screen and runs your `frame`. Read lamp-game.js's comments first. A TV app's page makes the
same renderer, sizes it to 1920x1080 at a pixel ratio of 1 (the page is laid out at that size and scaled), and draws
from its own `requestAnimationFrame`, moving by the time since the last frame.

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

Some platforms might not be powerful enough to run three.js.

## Checking it

`look_at_app` draws the preview on this Mac, which can't show a device's speed; its stats count draws and triangles a
frame, to compare with the budget in the request's device line. `look_at_app` with `on_device` opens the game where
Try On points and shows its log, with the real frame times.
