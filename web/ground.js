// Floor height under a point of the map, from the scan's point cloud, for
// placing places in 3D. Works on ramps and gradual slopes (the height comes
// from the points right under the spot, not from a level), under furniture
// (the lowest dense layer, not the table top), and on stacked floors (only
// heights near a reference are considered).
//
// Heights on places follow the apps: `y` is the *camera* height where the place
// was marked, i.e. floor + CAMERA_HEIGHT (BuildingLevels.cameraHeight).
//
// Plain script for the browser (exposes `Ground`) and a CommonJS module for the
// node tests. No DOM in here.
(function (root) {
  'use strict';

  const CAMERA_HEIGHT = 1.35;

  /// Points (Float32Array of x y z, y up) bucketed on the floor plane.
  function buildIndex(points, cell = 0.5) {
    const cells = new Map();
    for (let i = 0; i < points.length; i += 3) {
      const key = `${Math.floor(points[i] / cell)},${Math.floor(points[i + 2] / cell)}`;
      let list = cells.get(key);
      if (!list) cells.set(key, (list = []));
      list.push(i);
    }
    return { points, cell, cells };
  }

  function heightsNear(idx, x, z, radius) {
    const { points, cell, cells } = idx, r2 = radius * radius, ys = [];
    const i0 = Math.floor((x - radius) / cell), i1 = Math.floor((x + radius) / cell);
    const j0 = Math.floor((z - radius) / cell), j1 = Math.floor((z + radius) / cell);
    for (let i = i0; i <= i1; i++) for (let j = j0; j <= j1; j++) {
      const list = cells.get(`${i},${j}`); if (!list) continue;
      for (const k of list) {
        const dx = points[k] - x, dz = points[k + 2] - z;
        if (dx * dx + dz * dz <= r2) ys.push(points[k + 1]);
      }
    }
    return ys;
  }

  /// Floor height at (x, z), or null when the cloud has nothing there.
  /// `near`: only heights from `near - below` to `near + above` count — pass the
  /// height of what was clicked, or the floor of a neighbouring place, so a
  /// stacked floor or a walkway overhead is not mistaken for this floor.
  function floorAt(idx, x, z, { near = null, below = 2.0, above = 0.3, bin = 0.08, minCount = 6, layer = 0.25 } = {}) {
    for (const radius of [0.4, 0.8, 1.5]) {
      let ys = heightsNear(idx, x, z, radius);
      if (near !== null) ys = ys.filter(y => y >= near - below && y <= near + above);
      if (ys.length < minCount) continue;
      ys.sort((a, b) => a - b);
      // Lowest bin with enough points: the floor, not a table top or the ceiling.
      const counts = new Map();
      for (const y of ys) { const k = Math.floor(y / bin); counts.set(k, (counts.get(k) || 0) + 1); }
      const dense = [...counts.entries()].filter(([, c]) => c >= minCount).map(([k]) => k);
      if (!dense.length) continue;
      const lo = Math.min(...dense) * bin;
      // The surface layer from there up: its median follows a slope smoothly.
      const surface = ys.filter(y => y >= lo && y <= lo + layer);
      return surface[Math.floor(surface.length / 2)];
    }
    return null;
  }

  /// True when the surface at height `y` has another one 1.8–3.2 m below it:
  /// it is a ceiling over a room, not a floor. An upper storey's floor is not
  /// flagged: the ceiling under its slab is well under 1.8 m down, the floor
  /// below a full storey (3.5 m or more).
  function isCeiling(idx, x, z, y, opts) { return floorUnderCeiling(idx, x, z, y, opts) !== null; }

  /// The floor 1.8–3.2 m under a ceiling at height `y`, or null when `y` is not
  /// a ceiling. Floors are often sparse in a scan (plain, untextured), so a
  /// click from above may only ever touch the ceiling: this is the floor it meant.
  function floorUnderCeiling(idx, x, z, y, { min = 1.8, max = 3.2 } = {}) {
    return floorAt(idx, x, z, { near: y - min, below: max - min, above: 0, minCount: 3 });
  }

  /// `y` to store on a place standing on `floor`.
  const placeHeight = floor => floor + CAMERA_HEIGHT;
  /// The floor a place stands on, or null for places without a height.
  const floorOf = p => (typeof p?.y === 'number' ? p.y - CAMERA_HEIGHT : null);

  const api = { CAMERA_HEIGHT, buildIndex, floorAt, isCeiling, floorUnderCeiling, placeHeight, floorOf };
  root.Ground = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
