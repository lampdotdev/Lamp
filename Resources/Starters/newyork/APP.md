Kind: game, drawn with three.js (Lamp's runtime in Web/lamp-game.js), at home on the Mac.
Look: a sunlit 3D Manhattan at true scale, with a translucent dark heads-up display over it: the place and street at the
bottom left over a minimap, the modes (Walk, Drive, Cycle, Fly) at the bottom, the vehicle and its speed at the bottom
right, and time of day, Teleport, Map and sound at the top right.

# New York

Slop New York by Mr.doob (MIT, `Assets/Web/LICENSE-slop-newyork`): all of Manhattan from Harlem to the Battery, every
street and avenue where it really is, with landmarks, Central Park, piers, the other boroughs and New Jersey across the
water in less detail, traffic that keeps to its lanes and lights, people on the sidewalks, and trees.

- **Getting around**: 1 walk, 2 drive a yellow cab, 3 cycle, 4 fly a sightseeing helicopter. W A S D or the arrows,
  Shift boost, Space or E up and Q or C down in the helicopter, B horn. Dragging orbits the camera.
- **Cameras**: V (Shift-V back) or 5 to 0: the chase camera, an action camera, first person and scenic ones on Fifth
  Avenue, Times Square and the Chrysler Building.
- **The city**: time of day (golden hour, midday, dusk, night) from the buttons at the top, Teleport to a landmark, M
  the full map, H hides the HUD, N sound on or off. Every sound is synthesized.
- **A controller** paired with the device works too (`gamepad-controls.js`, from the original, reading the first pad Lamp's
  runtime gives each frame, which is also how Lamp's preview drives it): left stick move or steer,
  right stick look, RT and LT gas and brake (up and down in the helicopter), A jump, X boost, LB and RB change mode, Y
  the camera, R3 recentres it, the d-pad zooms, Menu the map and B closes it.
- The game remembers where the player was and in what between launches (`save('player')` from lamp-game.js).

## Code

- The page is `Web/`: `index.html` the page and the HUD's markup, `css/style.css` the HUD's look. Lamp's files beside
  it are `lamp-game.js` (the runtime: the frame, the pads, saves), `lamp.js` and `three/` (three.js with its WebGPU
  renderer and node materials, `three/webgpu` and `three/tsl`, drawing with WebGL 2), loaded through the import map.
- `Web/js`, all ES modules:
  - `main.js`: start-up, `QUALITY` (what's drawn), the HUD, keys, and `frame(f)`, which Lamp's runtime calls about 60
    times a second (`game({ renderer, frame, touch: false, keyboard: false })`: the city reads its own keys and draws its
    own touch controls; a controller comes as the first pad). Lamp draws it at 1920x1080 and fits that to the window.
  - The place: `nyc-geodata.js` (the real geography, generated data: don't edit by hand), `city-config.js` (streets,
    avenues, parks, shores in metres), `city-grid.js` and `buildings.js` (blocks and buildings), `landmarks.js`,
    `boroughs.js`, `road-network.js`, `road-paint.js`, `street-details.js` (lamps, signs, hydrants) and `trees.js`.
  - Looks: `tsl-materials.js` (every material, in TSL), `lighting.js` (`TIME_PRESETS`: sun, sky, fog for each time
    of day), `post-processing.js` (glow and colour grading), `vehicle-lights.js`.
  - Things that move: `controllers.js` (the four ways to move, their physics and keys), `traffic.js`,
    `pedestrians.js` and `pedestrian-routes.js`, `actor-models.js` (cars, people, the bike and the helicopter, built
    from shapes in code).
  - `cameras.js`, `nyc-map.js` (the minimap and the full map), `scene-culling.js`, `audio-*.js` (the synthesized
    sounds), `gamepad-controls.js`, `touch-controls.js` (shown on a touch screen).

## Data

Everything ships with the game: the map is in `nyc-geodata.js`, and nothing is fetched. No key or account.

## Easy to change

- Time of day and the sky's colours: `TIME_PRESETS` in `lighting.js`.
- How a building, the roads or the park look: `tsl-materials.js`, `buildings.js`.
- The vehicles: `actor-models.js`; how they drive, fly and how fast: `controllers.js`.
- How busy the streets are: the counts in `traffic.js` and `pedestrians.js`.
- The HUD: `index.html` and `css/style.css`.
- What's drawn: `QUALITY` in `main.js`. Street lights and reflections add several seconds to the start and are off.

Keep it smooth: try changes that draw more with the frame rate in the top left, and keep new geometry instanced or
merged like the rest. The whole city is built before the first frame, about half a minute in Lamp's preview: a look
takes that long. A change reopens the game, which comes back where the player was.
