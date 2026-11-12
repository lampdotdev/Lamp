Make the game start faster: most of the wait before "Compiling scene shaders" is laying the flat street level onto the hills, and it's the same work with the same result on every start.

1. Keep what draping makes. `setOnTerrain` (terrain.js) cuts and raises the same geometry from the same data every time: the road surface (one quad over the whole town, cut at a 3 cm tolerance, about 2 s), the sidewalks, lawns and driveways (about 6 s more) and the blocks' and street details' ground layers. Save the draped geometry the first time (keyed by the game's data and code, so a change to either makes it again) and load it on later starts instead of cutting it again.
2. For the first start, do the cutting in Web Workers, one per ground layer or tile, with the heights handed to them, so it runs on several cores rather than one.
3. Cut less: the road quad's 3 cm tolerance cuts the whole town finely. Use the ground's own grid for the road surface, or the 5 cm used elsewhere, wherever it looks the same.

Check how long each start stage takes (the "[init]" line) before and after, on a cold start and a second start.
