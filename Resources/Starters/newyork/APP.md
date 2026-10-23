Kind: game, a 3D web page (three.js) drawn by WebKit in the app's window.
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
- **A controller** paired with the Mac plays it like GTA V on a console (`gamepad-controls.js`): left stick move or
  steer, right stick look, RT gas or pedal or up, LT brake or down, RB handbrake, A boost, X jump, Y gets in and out,
  L3 horn, the d-pad changes vehicle and time of day, View the camera, Menu the map, with rumble on crashes.
- The game remembers where the player was and in what between launches (`localStorage`, "nyc-player-state").

## Code

- `Sources/App.swift`: the window. `Sources/GameView.swift`: the WebKit view, serving `Assets/Web` at
  `newyork://game/` (WebKit refuses modules and the import map to a page opened as a file), sound allowed without a
  click, the keyboard taken at once, and the page's console printed to the app's log as `[game] …`.
- `Assets/Web/index.html`: the page and the HUD's markup; `css/style.css` the HUD's look. `three-dev/`: three.js
  (WebGPURenderer and TSL, drawing with WebGL 2) and the few addons used, through the import map in index.html.
- `Assets/Web/js`, all ES modules:
  - `main.js`: start-up, `QUALITY` (what's drawn), the HUD, keys, the frame loop, and `adaptResolution` (drops the
    resolution on a Mac that can't hold 45 fps).
  - The place: `nyc-geodata.js` (the real geography, generated data: don't edit by hand), `city-config.js` (streets,
    avenues, parks, shores in metres), `city-grid.js` and `buildings.js` (blocks and buildings), `landmarks.js`,
    `boroughs.js`, `road-network.js`, `road-paint.js`, `street-details.js` (lamps, signs, hydrants) and `trees.js`.
  - Looks: `tsl-materials.js` (every material, in TSL), `lighting.js` (`TIME_PRESETS`: sun, sky, fog for each time
    of day), `post-processing.js` (glow and colour grading), `vehicle-lights.js`.
  - Things that move: `controllers.js` (the four ways to move, their physics and keys), `traffic.js`,
    `pedestrians.js` and `pedestrian-routes.js`, `actor-models.js` (cars, people, the bike and the helicopter, built
    from shapes in code).
  - `cameras.js`, `nyc-map.js` (the minimap and the full map), `scene-culling.js`, `audio-*.js` (the synthesized
    sounds), `gamepad-controls.js`, `touch-controls.js` (kept hidden on a Mac).

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
merged like the rest. A change to the page's files loads it again in the open app, which comes back where the player
was.
