// Lining up several Immersal point clouds, for the map editor. Mapper scans
// are gravity-aligned (y up), so a cloud's placement is a turn about the
// vertical plus an offset: {yaw, tx, ty, tz}. It carries the cloud's own
// coordinates into the map's frame with the apps' ImmersalAlignment convention
// on the floor plane (x' = c·x − s·z + tx, z' = s·x + c·z + tz); ty only lines
// up heights and is ignored by the apps.
//
// Matching is done in 3D: on the Flower Dome scans a top-down (2D) overlap
// barely changed when a cloud was shifted 2 m, because vegetation covers the
// whole floor plan, while the 3D shape (trunks, beds, the dome) is distinctive.
//
// Plain script for the browser (exposes `CloudAlign`) and a CommonJS module for
// the node tests. No DOM in here.
(function (root) {
  'use strict';

  function apply(p, x, y, z) {
    const c = Math.cos(p.yaw), s = Math.sin(p.yaw);
    return [c * x - s * z + p.tx, y + (p.ty || 0), s * x + c * z + p.tz];
  }

  /// One point per `voxel`-metre cell, so dense patches do not dominate a fit.
  function voxelize(points, voxel = 0.15) {
    const seen = new Set(); const out = [];
    for (let i = 0; i < points.length; i += 3) {
      const x = points[i], y = points[i + 1], z = points[i + 2];
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) continue;
      const k = `${Math.floor(x / voxel)},${Math.floor(y / voxel)},${Math.floor(z / voxel)}`;
      if (seen.has(k)) continue;
      seen.add(k); out.push(x, y, z);
    }
    return Float32Array.from(out);
  }

  function thin(points, count) {
    const step = Math.max(1, Math.floor(points.length / 3 / count));
    if (step === 1) return points;
    const out = []; for (let i = 0; i < points.length; i += 3 * step) out.push(points[i], points[i + 1], points[i + 2]);
    return Float32Array.from(out);
  }

  function centroid(points) {
    let x = 0, y = 0, z = 0; const n = points.length / 3 || 1;
    for (let i = 0; i < points.length; i += 3) { x += points[i]; y += points[i + 1]; z += points[i + 2]; }
    return [x / n, y / n, z / n];
  }

  function buildGrid(target, cell) {
    const grid = new Map();
    for (let i = 0; i < target.length; i += 3) {
      const k = `${Math.floor(target[i] / cell)},${Math.floor(target[i + 1] / cell)},${Math.floor(target[i + 2] / cell)}`;
      let b = grid.get(k); if (!b) grid.set(k, b = []);
      b.push(i);
    }
    return { grid, cell, target };
  }

  /// Nearest target point within `radius` (radius ≤ grid cell), or null.
  function nearest(g, x, y, z, radius) {
    const cx = Math.floor(x / g.cell), cy = Math.floor(y / g.cell), cz = Math.floor(z / g.cell);
    let best = -1, bestD = radius * radius;
    for (let a = -1; a <= 1; a++) for (let b = -1; b <= 1; b++) for (let c = -1; c <= 1; c++) {
      const bucket = g.grid.get(`${cx + a},${cy + b},${cz + c}`); if (!bucket) continue;
      for (const i of bucket) {
        const dx = g.target[i] - x, dy = g.target[i + 1] - y, dz = g.target[i + 2] - z, d = dx * dx + dy * dy + dz * dz;
        if (d < bestD) { bestD = d; best = i; }
      }
    }
    return best < 0 ? null : { i: best, d2: bestD };
  }

  /// Least-squares fit of a turn about y plus an offset, source pairs onto target pairs.
  function fitPairs(src, dst) {
    const n = src.length / 3;
    let ax = 0, ay = 0, az = 0, bx = 0, by = 0, bz = 0;
    for (let i = 0; i < src.length; i += 3) { ax += src[i]; ay += src[i + 1]; az += src[i + 2]; bx += dst[i]; by += dst[i + 1]; bz += dst[i + 2]; }
    ax /= n; ay /= n; az /= n; bx /= n; by /= n; bz /= n;
    let dot = 0, cross = 0;
    for (let i = 0; i < src.length; i += 3) {
      const sx = src[i] - ax, sz = src[i + 2] - az, tx = dst[i] - bx, tz = dst[i + 2] - bz;
      dot += sx * tx + sz * tz; cross += sx * tz - sz * tx;
    }
    const yaw = Math.atan2(cross, dot), c = Math.cos(yaw), s = Math.sin(yaw);
    return { yaw, tx: bx - (c * ax - s * az), ty: by - ay, tz: bz - (s * ax + c * az) };
  }

  /// Share of source points with a target point within `radius` under placement `p`.
  function overlap(source, g, p, radius) {
    let hit = 0; const n = source.length / 3;
    for (let i = 0; i < source.length; i += 3) {
      const [x, y, z] = apply(p, source[i], source[i + 1], source[i + 2]);
      if (nearest(g, x, y, z, radius)) hit++;
    }
    return n ? hit / n : 0;
  }

  /// Iterative closest point: refines placement `init` of `source` (own frame)
  /// onto `target` (map frame). A local refinement: the start must be within a
  /// couple of metres and a few tens of degrees.
  function icp(source, target, init, { iterations = 50, startRadius = 2, endRadius = 0.25, sample = 2500 } = {}) {
    const src = thin(source, sample);
    const g = buildGrid(target, startRadius);
    let p = { ty: 0, ...init }, rms = Infinity, inliers = 0;
    for (let it = 0; it < iterations; it++) {
      const radius = startRadius + (endRadius - startRadius) * (it / Math.max(1, iterations - 1));
      const a = [], b = []; let sq = 0;
      for (let i = 0; i < src.length; i += 3) {
        const [x, y, z] = apply(p, src[i], src[i + 1], src[i + 2]);
        const m = nearest(g, x, y, z, radius); if (!m) continue;
        a.push(src[i], src[i + 1], src[i + 2]); b.push(target[m.i], target[m.i + 1], target[m.i + 2]); sq += m.d2;
      }
      inliers = a.length / 3 / (src.length / 3);
      if (a.length < 60) break;
      rms = Math.sqrt(sq / (a.length / 3));
      p = fitPairs(a, b);
    }
    return { placement: p, rms, inliers };
  }

  /// How sure a placement is: the overlap at 25 cm, and the best overlap left
  /// after nudging it 1 m or 10° in any direction. A sharp drop means the
  /// clouds lock together there; a flat one means the fit could slide.
  function confidence(source, target, p, radius = 0.25) {
    const src = thin(source, 2500), g = buildGrid(target, radius);
    const at = q => overlap(src, g, q, radius);
    const fit = at(p);
    const [cx, cy, cz] = centroid(src); const [px, , pz] = apply(p, cx, cy, cz);
    const turned = d => { const q = { ...p, yaw: p.yaw + d }; const [qx, , qz] = apply(q, cx, cy, cz); q.tx += px - qx; q.tz += pz - qz; return q; };
    const nudged = Math.max(at({ ...p, tx: p.tx + 1 }), at({ ...p, tx: p.tx - 1 }), at({ ...p, tz: p.tz + 1 }), at({ ...p, tz: p.tz - 1 }),
      at(turned(0.1745)), at(turned(-0.1745)));
    return { fit, nudged, locked: fit >= 0.3 && fit - nudged >= 0.1 };
  }

  /// Every other cloud's points carried into the map frame: what one cloud is snapped onto.
  function targetFrom(clouds, exceptIndex) {
    const out = [];
    clouds.forEach((cl, i) => {
      if (i === exceptIndex || !cl.match || cl.hidden) return;
      for (let j = 0; j < cl.match.length; j += 3) out.push(...apply(cl.placement, cl.match[j], cl.match[j + 1], cl.match[j + 2]));
    });
    return Float32Array.from(out);
  }

  const api = { apply, voxelize, thin, centroid, fitPairs, overlap, icp, confidence, buildGrid, targetFrom };
  root.CloudAlign = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
