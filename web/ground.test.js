// node --test web/ground.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const G = require('./ground.js');

/// Floor points on a horizontal patch, as x y z triples.
function patch(out, x0, x1, z0, z1, yAt, density = 40, seed = 7) {
  let s = seed; const r = () => (s = (s * 16807) % 2147483647) / 2147483647;
  const n = Math.round((x1 - x0) * (z1 - z0) * density);
  for (let i = 0; i < n; i++) { const x = x0 + r() * (x1 - x0), z = z0 + r() * (z1 - z0); out.push(x, yAt(x, z), z); }
  return out;
}

test('flat floor: height is the floor wherever you ask', () => {
  const pts = Float32Array.from(patch([], 0, 10, 0, 10, () => 0.0));
  const idx = G.buildIndex(pts);
  assert.ok(Math.abs(G.floorAt(idx, 5, 5) - 0) < 0.06);
  assert.ok(Math.abs(G.floorAt(idx, 1.2, 8.7) - 0) < 0.06);
});

test('ramp: height follows the slope', () => {
  // rises 3 m over 10 m along x
  const pts = Float32Array.from(patch([], 0, 10, 0, 3, x => 0.3 * x));
  const idx = G.buildIndex(pts);
  for (const x of [1, 4, 8.5]) assert.ok(Math.abs(G.floorAt(idx, x, 1.5) - 0.3 * x) < 0.12, `x=${x}`);
});

test('table over the floor: the floor, not the table top', () => {
  const pts = patch([], 0, 6, 0, 6, () => 0);
  patch(pts, 2, 3, 2, 3, () => 0.75, 200);  // dense table top
  const idx = G.buildIndex(Float32Array.from(pts));
  assert.ok(Math.abs(G.floorAt(idx, 2.5, 2.5) - 0) < 0.06);
});

test('two stacked floors: the one near the reference height', () => {
  const pts = patch([], 0, 8, 0, 8, () => 0);
  patch(pts, 0, 8, 0, 8, () => 3.6, 40, 11);
  const idx = G.buildIndex(Float32Array.from(pts));
  assert.ok(Math.abs(G.floorAt(idx, 4, 4, { near: 0.5 }) - 0) < 0.06, 'lower floor');
  assert.ok(Math.abs(G.floorAt(idx, 4, 4, { near: 4.2 }) - 3.6) < 0.06, 'upper floor');
  // clicked a wall at chest height on the upper floor: still the upper floor
  assert.ok(Math.abs(G.floorAt(idx, 4, 4, { near: 4.8 }) - 3.6) < 0.06);
});

test('nothing under the spot: null', () => {
  const idx = G.buildIndex(Float32Array.from(patch([], 0, 2, 0, 2, () => 0)));
  assert.equal(G.floorAt(idx, 20, 20), null);
});

test('camera height convention matches the app (BuildingLevels.cameraHeight)', () => {
  assert.equal(G.CAMERA_HEIGHT, 1.35);
  assert.equal(G.placeHeight(0.4), 0.4 + 1.35);
  assert.equal(G.floorOf({ y: 2.0 }), 2.0 - 1.35);
  assert.equal(G.floorOf({}), null);
});

test('a ceiling is told apart from a floor, also between storeys', () => {
  // room: floor 0, ceiling 2.4
  const room = patch([], 0, 6, 0, 6, () => 0);
  patch(room, 0, 6, 0, 6, () => 2.4, 40, 3);
  const r = G.buildIndex(Float32Array.from(room));
  assert.equal(G.isCeiling(r, 3, 3, 2.4), true, 'the ceiling');
  assert.equal(G.isCeiling(r, 3, 3, 0), false, 'the floor');
  // two storeys: floor 0, ceiling 2.6, upper floor 3.6 (slab top), upper ceiling 6.2
  const two = patch([], 0, 6, 0, 6, () => 0);
  patch(two, 0, 6, 0, 6, () => 2.6, 40, 5);
  patch(two, 0, 6, 0, 6, () => 3.6, 40, 9);
  patch(two, 0, 6, 0, 6, () => 6.2, 40, 13);
  const t = G.buildIndex(Float32Array.from(two));
  assert.equal(G.isCeiling(t, 3, 3, 3.6), false, 'upper floor is a floor');
  assert.equal(G.isCeiling(t, 3, 3, 6.2), true, 'upper ceiling');
  assert.equal(G.isCeiling(t, 3, 3, 2.6), true, 'lower ceiling');
});

test('sparse floor under a dense ceiling: the floor under the ceiling', () => {
  const pts = patch([], 0, 6, 0, 6, () => -1.5, 6, 21);   // few floor points
  patch(pts, 0, 6, 0, 6, () => 0.6, 300, 23);              // dense ceiling 2.1 m up
  const idx = G.buildIndex(Float32Array.from(pts));
  const f = G.floorUnderCeiling(idx, 3, 3, 0.6);
  assert.ok(f !== null && Math.abs(f + 1.5) < 0.08, String(f));
  assert.equal(G.floorUnderCeiling(idx, 3, 3, -1.5), null, 'a floor has no floor under it');
});
