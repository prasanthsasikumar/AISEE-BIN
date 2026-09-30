// node --test web/align.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const A = require('./align.js');

/// A room-like cloud with distinctive 3D structure: walls, a few "trunks" and a bench.
function scene(seed = 1) {
  let s = seed; const r = () => (s = (s * 16807) % 2147483647) / 2147483647;
  const pts = [];
  for (let i = 0; i < 3000; i++) { const t = r() * 12; pts.push(t, r() * 3, 0); pts.push(0, r() * 3, t * 0.7); }  // two walls
  for (const [cx, cz, h] of [[3, 2, 2.5], [7, 5, 1.2], [5, 7, 3], [9, 3, 1.8]]) {
    for (let i = 0; i < 600; i++) { const a = r() * 6.28; pts.push(cx + 0.3 * Math.cos(a), r() * h, cz + 0.3 * Math.sin(a)); }
  }
  for (let i = 0; i < 800; i++) pts.push(2 + r() * 3, 0.45 + r() * 0.05, 8 + r() * 0.6);                     // bench
  return Float32Array.from(pts);
}

/// The inverse of a placement, to make a "scan" in its own frame from the map-frame scene.
function unplace(points, p) {
  const out = new Float32Array(points.length), c = Math.cos(-p.yaw), s = Math.sin(-p.yaw);
  for (let i = 0; i < points.length; i += 3) {
    const x = points[i] - p.tx, z = points[i + 2] - p.tz;
    out[i] = c * x - s * z; out[i + 1] = points[i + 1] - p.ty; out[i + 2] = s * x + c * z;
  }
  return out;
}

test('fitPairs recovers a turn and offset exactly', () => {
  const truth = { yaw: 0.7, tx: 3, ty: -0.5, tz: -2 };
  const src = A.voxelize(scene(), 0.2);
  const dst = []; for (let i = 0; i < src.length; i += 3) dst.push(...A.apply(truth, src[i], src[i + 1], src[i + 2]));
  const p = A.fitPairs(src, Float32Array.from(dst));
  for (const k of ['yaw', 'tx', 'ty', 'tz']) assert.ok(Math.abs(p[k] - truth[k]) < 1e-4, `${k} ${p[k]}`);
});

test('icp snaps a roughly placed cloud and confidence calls it locked', () => {
  const map = A.voxelize(scene(1), 0.15);
  const truth = { yaw: 2.2, tx: 14, ty: 0.6, tz: -9 };
  const scan = A.voxelize(unplace(scene(2), truth), 0.15);           // another scan of the same room
  const rough = { yaw: truth.yaw + 0.2, tx: truth.tx + 0.8, ty: 0, tz: truth.tz - 0.9 };
  const r = A.icp(scan, map, rough);
  assert.ok(Math.abs(r.placement.yaw - truth.yaw) < 0.02, `yaw ${r.placement.yaw}`);
  assert.ok(Math.hypot(r.placement.tx - truth.tx, r.placement.tz - truth.tz) < 0.1, `t ${r.placement.tx},${r.placement.tz}`);
  assert.ok(Math.abs(r.placement.ty - truth.ty) < 0.1, `ty ${r.placement.ty}`);
  const c = A.confidence(scan, map, r.placement);
  assert.ok(c.locked, JSON.stringify(c));
  assert.ok(!A.confidence(scan, map, rough).locked || A.confidence(scan, map, rough).fit < c.fit);
});

test('a placement far off is not reported as locked', () => {
  const map = A.voxelize(scene(1), 0.15);
  const scan = A.voxelize(scene(2), 0.15);
  const c = A.confidence(scan, map, { yaw: 1.5, tx: 30, ty: 0, tz: 30 });
  assert.equal(c.locked, false);
  assert.equal(c.fit, 0);
});

test('targetFrom carries other clouds into the map frame and skips hidden ones', () => {
  const pts = Float32Array.from([1, 0, 0]);
  const clouds = [
    { match: pts, placement: { yaw: 0, tx: 0, ty: 0, tz: 0 } },
    { match: pts, placement: { yaw: Math.PI / 2, tx: 5, ty: 1, tz: 0 } },
    { match: pts, placement: { yaw: 0, tx: 9, ty: 0, tz: 9 }, hidden: true },
  ];
  const t = A.targetFrom(clouds, 0);
  assert.equal(t.length, 3);
  assert.ok(Math.abs(t[0] - 5) < 1e-6 && Math.abs(t[1] - 1) < 1e-6 && Math.abs(t[2] - 1) < 1e-6);
});
