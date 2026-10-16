---
name: maps
description: A real place from map data (OpenStreetMap) - a town to drive or walk through, a campus, a neighbourhood, with its buildings, roads and shops. Read before fetching or drawing map data.
---

# Real places from map data

A real place (a town to drive, a campus, a neighbourhood) comes from OpenStreetMap. Fetch it from the Overpass API (overpass-api.de, else a mirror), one bounding-box query, waiting and trying again when it's busy; never OpenStreetMap's own editing API, which its rules keep from bulk downloads. Turn it, while building, into a compact file in Assets/ that the app reads (metres from a centre point, footprints already triangulated), not raw OSM parsed at launch. Worth reading: each building's footprint, `height` or else `building:levels` (about 3.3 m a floor) or else a guess from `building` (house, garage, apartments, university…), `roof:shape`, and `building:part` for landmarks' stepped parts; roads with `highway`, `width` or `lanes`, `oneway` and `name`; traffic signals, crossings, parks, water, car parks and trees; shops and amenities with `name`, `opening_hours` and address. Colours and façades aren't in it: choose them from the building's type. In a 3D scene, stream the world by tile (the scene-3d skill's `scene.stream`), and show "© OpenStreetMap contributors" on screen.
