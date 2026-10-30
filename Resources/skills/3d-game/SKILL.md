---
name: 3d-game
description: 3D games and scenes in a web page with three.js, on any device that runs web, TVs included - which library 3D is drawn with, loading it and the renderer on Lamp's game runtime or in a TV or device page, models, light and materials, physics with Rapier (things that fall, roll, stack and collide, a player that walks on them, a car on its wheels), and what costs the most. Read before writing or changing 3D in a web page.
---

# 3D in a web page

three.js runs in a page wherever the device takes a page (`make_app_for`'s table) and its browser gives WebGL 2: a
host for the page isn't enough on its own, so check WebGL 2 first (below). What differs then is speed: a Mac draws far
more than a phone, and a TV's chip is often slower than a phone's. Nothing here limits what you make; it says what
costs the most, so you can choose what the game is worth on the devices it's played on.

Lamp ships three.js in two kinds of page: a game's page on its runtime (`make_app_for` with `kind` "game"), and a page
with no runtime: a Samsung or LG TV app's page, or a device integration's web app whose rules name the 3D library's folder. A page with no
runtime has no game runtime, no Phaser bridge and no Rapier: it loads three.js from the folder its rules give and makes
its own renderer and frame loop (below).

A 3D game is made this way by default, on every device Lamp has a host for a page on, the Mac included. 3D in Swift,
in a Mac app made natively (because the person asked for native, or the app was made so), is the scene-3d skill's
(RealityKit through LampSceneView); native 3D on iPhone, iPad or Apple TV is written with that device's own
frameworks. A game whose play is flat is better made in 2D with Phaser (the 2d-game skill), which also runs where a
TV's browser has no WebGL 2. The game skill holds what every game needs
(the frame loop, controls, sound, saves); read it too.

## The renderer

### A game on Lamp's runtime

index.html loads lamp.js, then the scaffold's import map, then game.js as a module: keep that. The import map's
`three` and `three/addons/` come from `Web/three`: the WebGL build and its addons such as GLTFLoader. `three/webgpu`
and `three/tsl` (node materials, drawing with WebGL 2) are added once the page imports them, and only a heavy scene
needs them. Nothing else is there, so no Draco or KTX2 files (the `assets` tool brings in none), and nothing is
loaded from the network. Physics is
Rapier, mapped in the import map when a game needs it (Physics, below).

game.js makes one `THREE.WebGLRenderer({ antialias: true })` and calls `game({ renderer, init, frame, touch })` from
lamp-game.js once:

- Lamp sizes the canvas to 1920x1080 and fits it to the window or screen.
- `init` runs once, before the first frame. It may be async, to load models with
  `new GLTFLoader().loadAsync('ship.glb')` or sounds; make or load every sound here. It starts the game where
  `pendingRestore()` says, after a change of its code: `const was = pendingRestore();` then the level, the player,
  the camera and the open menu or overlay from `was` when there is one, and the title or intro only when there isn't
  (the game skill, "Changes while it's played"; the game-ui skill says what the title and menus are).
- `frame(f)` runs about 60 times a second. It reads the controller as `f.pads[0]`, moves things by `f.dt` (and
  `f.time`), and ends with `renderer.render(scene, camera)`.
- `touch` names the buttons Lamp's touch controls show on a phone or tablet.
- game.js only puts the parts together, and keeps the renderer and the world's parts with `hot(import.meta).keep`
  (the game skill, "Changes while it's played", has the recipe). The world is built in parts (the ground, the
  buildings, the trees and street details, the props, the traffic), each in a module of its own and into a group of
  its own, so a change to one part builds only that part again; each thing that moves or changes in play (the player,
  a vehicle, the camera, enemies, the HUD's code) is a class in a module that ends with `hot(import.meta).accept()`,
  so a change to its methods goes into the running scene with nothing built again. A uniform's value or a material's
  color set in an `update` swaps; a material made anew compiles its shader again as it's first drawn.

A page laid out at the window's size whose HUD is its own HTML (a strategy game, a page made for phones as well as
TVs) passes `fill: true` to `game()` and places and sizes its canvas itself, drawing it smaller when frames run slow;
the rest of this section is for a game drawn at 1920x1080.

When frames run slow, Lamp draws the game smaller and scales it up to the screen by itself (`sharp: true` in `game()`
keeps it at 1920x1080), so size anything drawn off-screen (a render target, a post-process pass) from
`renderer.getSize()`, never from 1920x1080. Read lamp-game.js's comments first: they're the whole interface.

### A page with no runtime (a TV app, a device's web app)

The page's rules name the folder Lamp writes three.js in and the path the page reaches it at (`./three/` in a Samsung
or LG TV app's Web/). Lamp writes that folder before every build: never edit it. In index.html, after lamp.js, put the
import map with that path:

```html
<script type="importmap">{ "imports": { "three": "./three/three.module.js", "three/addons/": "./three/addons/" } }</script>
```

then the 3D code in a `<script type="module">` (or a module file of your own beside it), with
`import * as THREE from 'three'` and addons from `'three/addons/…'`. Use this three.js for anything 3D, never another
engine or one from the network. Make the renderer yourself, sized to 1920x1080 at a pixel ratio of 1 (the page is laid
out at that size and scaled), and draw from your own `requestAnimationFrame`, moving everything by the time since the
last frame. Modules and import maps need a newer TV browser than the oldest the TV rules allow for, and three.js needs
WebGL 2 (next).

The three.js Lamp ships asks the browser only for a WebGL 2 context and stops with an error when it gets none, so
WebGL 2 comes before anything else here: check on the device that a canvas gives one (log whether
`canvas.getContext('webgl2')` returns a context, and read the log with `look_at_app` and `on_device`). Most browsers
have it; not every Samsung TV does. Where it's missing, make the game another way (2D with Phaser, which draws with WebGL 1 or a plain canvas, or native on that
device) or tell the person why 3D in a page can't run there.

## Models, light and materials

- Before building a game's buildings, vehicles, characters or trees in code, look in Lamp's free models (`assets` with
  `find` and `show`; the assets skill): many distinct things, and anything that walks or runs, come out better
  ready-made. Shapes made in code (boxes, spheres, cylinders, extruded outlines), well lit and colored, often look better than
  mismatched models, and cost little. Build each character and prop as a `THREE.Group` of them in a function of its
  own (a body, a head, eyes that blink, wheels that turn, a tail that wags), its parts named so they can move, and
  give it a little life: a bob, a lean into a turn, a squash on landing. A model file (a .glb) is one the person
  gave or named, or a ready-made one from the `assets` tool (buildings, vehicles, characters with animations, trees:
  the assets skill says when they suit and how to scale, turn, copy and animate them). It goes in Web/ and loads once
  in `init` with lamp-game.js's `model('ship.glb')` (a group holding its scene, with `group.animations`), and a picture with
  `texture('bricks.png', t => { t.colorSpace = THREE.SRGBColorSpace; })`: a new copy of either goes into the running
  game, inside the same group or texture. A clone of the model, or a mixer playing its animations, is made again in
  `assetChanged(path)` (the game skill, "Changes while it's played").
- One or two lights computed in the shader are the safe start. MeshStandardMaterial looks good under them;
  MeshLambertMaterial or MeshBasicMaterial cost less.
- Make every mesh, material and texture once in `init` and reuse it; many copies of one shape are one
  `THREE.InstancedMesh`.

## Physics

**Whether a game needs it.** Most don't. A runner, a shooter, a racer on a track or a platformer on flat ground moves
things by its own rules and tests what touches what itself: the distance between two centers, two boxes
(`THREE.Box3`), a ray down to the ground over a few meshes (`THREE.Raycaster`). That costs nearly nothing and does
exactly what the game means. Physics is for games whose fun is things behaving like things: a stack of crates that
topples, marbles that roll and knock into each other, a board that tilts, a ball through pins, a car on its
suspension, a door on a hinge, a chain, a pile of anything. Once a game starts writing its own bounces, stacking or
rolling, it wants physics: hand-made physics is where objects sink, jitter and pass through walls.

**Rapier.** Lamp ships Rapier, a physics engine in WebAssembly, as one module that loads like three.js does,
wherever the game is played. It's for a game's page on its runtime; a TV app's page doesn't get it. Add it to the import map in index.html,
`"@dimforge/rapier3d-compat": "./rapier/rapier.js"`, and Lamp puts `Web/rapier/` beside the page (it's Lamp's, like
`Web/three/`; a game that doesn't import it doesn't carry it). Start it once, in `init`, and step the world with
`fixedStep` from lamp-game.js:

```js
import * as THREE from 'three';
import RAPIER from '@dimforge/rapier3d-compat';
import { game, fixedStep } from './lamp-game.js';

let world, events, physics, pad, presses = 0;
game({ renderer, async init() {
    await RAPIER.init();
    world = new RAPIER.World({ x: 0, y: -9.81, z: 0 });
    events = new RAPIER.EventQueue(true);
    physics = fixedStep(() => { steer(); world.step(events); events.drainCollisionEvents(hit); });
    // … the ground, the bodies and their meshes
}, frame(f) {
    pad = f.pads[0];
    presses |= pad.pressed;   // kept until a step uses them
    physics(f.dt);
    place();
    renderer.render(scene, camera);
} });

function steer() {
    // Held buttons and sticks are read as they are now, every step.
    ball.applyImpulse({ x: pad.lx * PUSH, y: 0, z: -pad.ly * PUSH }, true);
    // A press is used by one step only: a frame can run no step (at 120 frames a second) or two (at 30).
    if (presses & CONTROLS.jump) ball.applyImpulse({ x: 0, y: JUMP, z: 0 }, true);
    presses = 0;
}
```

- `await RAPIER.init()` goes inside `init` (never at the top of the module), so a failure is the game's start-up
  error, which the preview reports.
- The world steps 1/60 s at a time (`world.timestep`, its default), the step `fixedStep` runs as often as the frame
  needs, so the game plays the same at 30, 60 or 120 frames a second and the preview replays it exactly: the same
  moves give the same tumble every play. Never pass `f.dt` to the world or change `timestep` per frame. Anything that
  pushes bodies (the controls, a motor) runs inside the step, as `steer()` does above, reading the pad the frame
  kept. A press (`pressed`, `released`) belongs to a frame, not a step: gather it into `presses` in `frame` and let the
  first step that runs use it and clear it, or a jump is lost at 120 frames a second and done twice at 30. Anything
  random in the setup comes from `random()`.
- Meters, kilograms and seconds, y up, as three.js has them. Keep things their real size: a box a meter across, a
  marble a few centimeters. Rapier's tolerances are tuned for things about a meter across: in a world of small things
  (a tabletop maze, marbles, dice) set `world.lengthUnit` to their typical size in meters (0.05 for marbles), or they
  sink into each other and jitter. Small fast things can pass through thin walls between steps: make walls thick, or
  give the fast body `setCcdEnabled(true)`.

**Bodies and colliders.** A body is how a thing moves; its colliders are its shape.

- Fixed (`RigidBodyDesc.fixed()`): what never moves, the ground, walls, the track.
- Dynamic (`RigidBodyDesc.dynamic()`): moved only by physics, crates, balls, debris. Push it with `applyImpulse` (a
  kick) or `addForce` (a steady push), never by setting its position each frame.
- Kinematic (`RigidBodyDesc.kinematicPositionBased()`): moved by the game, pushing dynamic bodies without being
  pushed back: a moving platform, a tilting board, a door the game opens. Give it its place each step with
  `setNextKinematicTranslation` and `setNextKinematicRotation`.

Colliders are simple shapes: `ColliderDesc.cuboid`, `ball`, `capsule`, `cylinder`, `roundCuboid` (a box with
rounded edges rolls and stacks more kindly), several on one body for a shape made of parts (a table: a top and four
legs). A model's look never becomes its collider: an odd shape that moves is a `convexHull` of a few of its points,
a level that never moves may be a `trimesh` of a simplified mesh, and land is a `heightfield`. Bounce, grip and weight
are the collider's: `setRestitution`, `setFriction`, `setDensity`.

**Meshes in step with bodies.** Keep each body with the mesh that shows it and copy the body onto the mesh after the
step, straight into three.js's own objects, so nothing is allocated per frame:

```js
const things = [];   // { body, mesh }
function place() {
    for (const t of things) { t.body.translation(t.mesh.position); t.body.rotation(t.mesh.quaternion); }
}
```

Many of one thing (a hundred crates) are one `THREE.InstancedMesh`: read each body into one Vector3 and Quaternion
kept for it, `matrix.compose(position, quaternion, scale)`, `setMatrixAt(i, matrix)`, and set `instanceMatrix.needsUpdate`.

**The player.** A character that walks, climbs steps and stands on slopes is a kinematic body with a capsule and
Rapier's character controller, rather than a dynamic ball pushed around:

```js
const controller = world.createCharacterController(0.02);
controller.enableAutostep(0.3, 0.2, true);   // steps up to 30 cm
controller.enableSnapToGround(0.3);
controller.setMaxSlopeClimbAngle(45 * Math.PI / 180);
// each step: where the player wants to go this step, gravity included
controller.computeColliderMovement(playerCollider, wanted);
const moved = controller.computedMovement(), at = playerBody.translation();
playerBody.setNextKinematicTranslation({ x: at.x + moved.x, y: at.y + moved.y, z: at.z + moved.z });
const grounded = controller.computedGrounded();   // may jump
```

The game keeps the player's own vertical speed (gravity added each step, set on a jump, zeroed when grounded).

**A vehicle.** A car is a dynamic body (a box for the chassis, its weight low) and Rapier's vehicle controller, which
casts a ray for each wheel and gives it suspension and grip:

```js
const car = world.createVehicleController(chassis);
const down = { x: 0, y: -1, z: 0 }, axle = { x: -1, y: 0, z: 0 };
for (const [x, z] of [[-0.8, 1.3], [0.8, 1.3], [-0.8, -1.3], [0.8, -1.3]]) car.addWheel({ x, y: 0, z }, down, axle, 0.3, 0.35);
// each step: steering on the front wheels, engine and brake on the back
car.setWheelSteering(0, steer); car.setWheelSteering(1, steer);
car.setWheelEngineForce(2, gas); car.setWheelEngineForce(3, gas);
car.updateVehicle(world.timestep);
```

Wheels are drawn from the controller (`wheelSuspensionLength(i)`, `wheelRotation(i)`, `wheelSteering(i)`), not given
bodies of their own. Tune `setWheelFrictionSlip` and the suspension by driving it in the preview.

**Joints** hold two bodies together: `RAPIER.JointData.revolute` (a hinge: a door, a wheel, a flipper),
`prismatic` (a slider), `spherical` (a ball joint: a chain link, a pendulum), `fixed` (welded), made with
`world.createImpulseJoint(data, body1, body2, true)`. A hinge can be driven with `configureMotorVelocity`.

**What touched what.** Give a collider `setActiveEvents(RAPIER.ActiveEvents.COLLISION_EVENTS)` and read
`events.drainCollisionEvents((a, b, started) => …)` after each step, a pair of collider handles: keep a `Map` from
handle to the game's thing. A sensor (`setSensor(true)`) is a zone that's felt but not hit: a goal, a pickup, a
checkpoint. A collision is the moment for a sound and a rumble.

**Keeping it light.** Physics runs on the CPU, before anything is drawn, so it takes from the same 16 ms. Resting
bodies fall asleep by themselves and then cost almost nothing: leave them be (don't set their position or velocity
unless something happens to them), and when the game moves a sleeping one itself, `wakeUp()` it. Balls, boxes and
capsules are cheapest; convex hulls cost more, trimeshes most. Where the request's device line names a slow place
(a TV, a streamer, an older console), keep to about 100 dynamic bodies awake at once, with a few hundred more asleep or
fixed; a Mac takes a thousand. Step only through `fixedStep`, never make a body or collider per frame (make them in `init` or when a level starts, and reuse them), and remove what
falls out of the world (`world.removeRigidBody`). The device's log says how its frames keep to time: when they're late
with physics in play, make fewer bodies move at once before drawing less.

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
Play it as the game skill's "Playtesting" says before you finish.
