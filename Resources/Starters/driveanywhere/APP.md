Kind: game, a 3D scene in RealityKit (LampScene).
Look: an open-world driving game in the real place, built from the map: real streets, buildings at their mapped
heights, real shops; a heads-up display over it with a rotating minimap, the area and street, and the speed.

# Drive Anywhere

A driving game on real streets anywhere in the world. Everything is built as the game runs from OpenStreetMap
around a point: roads at their mapped widths with lanes, markings, crosswalks, kerbs and sidewalks; every building
in its footprint, height and roof; parks, water, parking lots, railways, street lamps and hydrants; the land's own
hills from open elevation tiles. It opens on downtown San Francisco, and Travel (T) goes anywhere Apple Maps can find.

- **Driving**: the player starts in a random vehicle (sedans to fire trucks, a monster truck, a golf cart). W A S D
  or the arrows, Space handbrake, Shift boost, R back onto the nearest street, E horn, Q siren on emergency
  vehicles, G the vehicle's own action (tip the dump truck, raise the ladder, the ice cream tune).
- **On foot**: F gets out, and F again takes the nearest parked or passing car (its driver runs off), a rider's
  bike or scooter, or the controls of a passing train.
- **The city lives**: traffic follows the lanes and stops at working lights and stop signs, pedestrians walk the
  sidewalks and cross at corners, riders on bikes, scooters and skateboards, trains on the mapped lines with
  level crossings. Everything can be hit: cars tumble and right themselves, people are knocked flat and get up,
  trees, signs, poles and lamps go over, hydrants burst. Buildings stay solid; water is a hazard.
- **Directions**: M opens a big map to drag and zoom; click anywhere, or search a shop, street or address, and the
  HUD gives turn-by-turn directions along the street graph.
- **Shops**: mapped businesses get storefronts, awnings, signs and OPEN signs that follow their real hours, and a
  card as the car passes.
- **Time of day**: the sky follows the real sun at the place; at night lamps and windows light up.
- **Local habits**: which side of the road traffic keeps to, mph or km/h, line colours and street-sign colours follow
  the country (`RegionStyle.forCountry`).
- F3 shows frame rate and timings.

## Code

- `App.swift`: the window. `GameView.swift`: `Game`, the one model (building the world, the player, vehicles and
  their controls, the camera, the HUD's numbers), and `GameScreen`, which holds the `LampSceneView`.
- `CityConfig.swift`: the place (`CityConfig`: name, centre, start, downtown size) and the country's habits
  (`RegionStyle`). `Travel.swift`: `TravelPlace` (kept), the suggestions and the Travel sheet.
- The map: `CityLoader.swift` (the Overpass API with its mirrors, the downtown made once), `TileStreamer.swift`
  (500 m tiles round the car, along a trip and where the big map looks), `TileProcessor.swift` (OpenStreetMap data
  into roads, buildings, areas, shops and furniture, off the main thread), `CityData.swift` (the data types, road
  graph, collision grids, neighbourhoods), `Terrain.swift` (elevation, `w3` puts anything on the ground).
- Drawing: `CityTiles.swift` streams 150 m squares round the car through `scene.stream`; `CityGeometry.swift` works
  out a square's meshes off the main thread (roads, markings, buildings, roofs, signs, signals, parking, pitches,
  gas stations); `CityBuilder.swift` makes them into entities with shared materials; `Storefronts.swift`,
  `Furniture.swift`, `TextAtlas.swift` (all lettering in one texture), `MapShapes.swift`, `Props.swift` (mesh
  builder, trees).
- Things that move: `VehicleModels.swift` (`CarStyle`: each vehicle's model, colour, handling, engine note and the
  traffic and parked mixes), `CarPhysics.swift` (bodies, collisions, knocks), `Traffic.swift`, `Pedestrians.swift`,
  `Riders.swift` and `RideModels.swift`, `Railway.swift` and `TrainModels.swift`, `TreeFall.swift`, `Geysers.swift`,
  `CrashFX.swift`.
- `HUD.swift` (minimap, area, speed, boost, controls), `Navigation.swift` (routing and search), `MapSheet.swift`
  (the big map), `Businesses.swift` and `BusinessCard.swift` (shops and their hours), `Sound.swift` (every sound is
  synthesized), `Perf.swift` (the F3 readout).
- `LampScene.swift` and `LampSupport.swift` are Lamp's.

## Data

Nothing about a place ships with the game. Map data comes from the Overpass API (three public servers tried in turn,
one or two requests at a time, each answer kept), elevation from the open Terrain Tiles on AWS, and Travel's search
from Apple Maps; none needs a key. Everything fetched is kept per place in `~/Library/Caches/DriveAnywhere/<place>/`
(`CityConfig.cacheFolder`), so a place is downloaded once; bump `CityLoader.version` when the rules that read the map
change. The credit "© OpenStreetMap contributors" stays on screen (the HUD and the big map): the map's licence asks
for it. LampStore keeps where the game is ("place") and the recent places ("recentPlaces").

## Easy to change

- Where it starts and the suggestions: `TravelPlace.sanFrancisco` and `TravelPlace.suggestions`.
- Vehicles: a `CarStyle` case with its model in `VehicleModels.swift`, its `handling`, `enginePitch` and place in
  `randomTraffic`/`parked`.
- How busy the streets are: the counts in `Game.build` (traffic, pedestrians, riders).
- Driving feel: `Handling` per vehicle, and `Game.drive` (boost, handbrake). How hard crashes are: `Physics.knock`.
- Time of day: `DayTime` (`DayTime.override` forces day, sunset or night).
- How a kind of building or shop looks: `CityGeometry` (windows, roofs) and `ShopLook` in `Storefronts.swift`.
- The HUD and its colours: `HUD.swift`.

Keep it smooth: a square must take a few milliseconds on the main thread, so work out geometry in
`CityGeometry` (off the main thread) and share materials and models; look at the F3 readout after a change that
draws more.
