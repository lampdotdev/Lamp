const TERRAIN_REVS = typeof __TERRAIN_REVS__ === "undefined" ? {} : __TERRAIN_REVS__;

/** Requests for map art, revision query and all: the service worker serves them cache-first. */
export const MAP_ART = /\/assets\/maps\/.*\.webp(\?|$)/;

export function mapAssetBase(mapId) {
    return `assets/maps/${mapId}`;
}

/** A painted terrain chunk (column c, row r) of a map, at its current revision. */
export function terrainChunkUrl(mapId, c, r, revs = TERRAIN_REVS) {
    const rev = revs[mapId];
    return `${mapAssetBase(mapId)}/t_${c}_${r}.webp${rev ? `?v=${rev}` : ""}`;
}
