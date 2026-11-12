// Tidying a walked route, for the map editor. The same two passes as the
// phone's RouteTidy.swift (keep the two in step; both are tested against the
// AHLab Level 3 walk of 12 Nov 2026):
//
// 1. Waypoints (junctions) closer than MERGE_RADIUS are one corner: merge them.
// 2. A link that passes within SNAP_RADIUS of another point runs along ground
//    that point is on: route it through the point.
//
// A mapping walk is one chain in walking order, so doubling back leaves two
// waypoints for one corner and long links laid over corridor already drawn.
// Marked places are never merged or moved.
//
// Plain script for the browser (exposes `RouteTidy`) and a CommonJS module for
// the node tests. No DOM in here.
(function (root) {
  'use strict';

  const MERGE_RADIUS = 2.0, SNAP_RADIUS = 1.0, FLOOR_GAP = 1.5;

  const sameFloor = (a, b) => typeof a.y !== 'number' || typeof b.y !== 'number' || Math.abs(a.y - b.y) < FLOOR_GAP;
  const dist = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);

  /// Returns { graph, mergedWaypoints, reroutedLinks, changed }. `graph` is a
  /// new object when something changed, else the one passed in. Every other
  /// field of the graph and of its points and links is carried over.
  function tidy(graph) {
    let pois = graph.pois.map(p => ({ ...p }));
    const known = new Set(pois.map(p => p.id));
    let links = [];   // { from, to, ...rest } without repeats
    const has = (list, a, b) => list.some(e => (e.from === a && e.to === b) || (e.from === b && e.to === a));
    const add = (list, e) => { if (e.from !== e.to && !has(list, e.from, e.to)) list.push(e); };
    const dangling = [];
    for (const e of graph.edges) (known.has(e.from) && known.has(e.to) ? add(links, { ...e }) : dangling.push(e));
    let mergedWaypoints = 0, reroutedLinks = 0;

    for (;;) {
      let best = null;
      for (let i = 0; i < pois.length; i++) {
        if (pois[i].category !== 'junction') continue;
        for (let j = i + 1; j < pois.length; j++) {
          if (pois[j].category !== 'junction' || !sameFloor(pois[i], pois[j])) continue;
          const d = dist(pois[i], pois[j]);
          if (d < MERGE_RADIUS && (!best || d < best.d)) best = { i, j, d };
        }
      }
      if (!best) break;
      const keep = pois[best.i], drop = pois[best.j];
      keep.x = (keep.x + drop.x) / 2; keep.z = (keep.z + drop.z) / 2;
      if (typeof keep.y === 'number' && typeof drop.y === 'number') keep.y = (keep.y + drop.y) / 2;
      else if (typeof drop.y === 'number') keep.y = drop.y;
      pois.splice(best.j, 1);
      const relinked = [];
      for (const e of links) add(relinked, { ...e, from: e.from === drop.id ? keep.id : e.from, to: e.to === drop.id ? keep.id : e.to });
      links = relinked;
      mergedWaypoints++;
    }

    const byId = id => pois.find(p => p.id === id);
    for (let i = 0; i < links.length;) {
      const e = links[i], a = byId(e.from), b = byId(e.to);
      const via = pointOn(a, b, pois);
      if (!via) { i++; continue; }
      links.splice(i, 1);
      add(links, { ...e, to: via.id });
      add(links, { ...e, from: via.id });
      reroutedLinks++;
      i = 0;
    }

    const changed = mergedWaypoints > 0 || reroutedLinks > 0;
    return { graph: changed ? { ...graph, pois, edges: links.concat(dangling) } : graph, mergedWaypoints, reroutedLinks, changed };
  }

  /// The point nearest the line a–b that stands on it, clear of both ends.
  function pointOn(a, b, pois) {
    const abx = b.x - a.x, abz = b.z - a.z, len2 = abx * abx + abz * abz;
    if (!(len2 > 0)) return null;
    let best = null, bestD = Infinity;
    for (const c of pois) {
      if (c.id === a.id || c.id === b.id || !sameFloor(a, c) || !sameFloor(b, c)) continue;
      const t = ((c.x - a.x) * abx + (c.z - a.z) * abz) / len2;
      if (!(t > 0 && t < 1)) continue;
      const d = Math.hypot(c.x - (a.x + t * abx), c.z - (a.z + t * abz));
      if (d < SNAP_RADIUS && dist(c, a) > SNAP_RADIUS && dist(c, b) > SNAP_RADIUS && d < bestD) { best = c; bestD = d; }
    }
    return best;
  }

  /// "1 waypoint merged, 4 links re-routed"
  function summary(r) {
    const parts = [];
    if (r.mergedWaypoints) parts.push(`${r.mergedWaypoints} waypoint${r.mergedWaypoints === 1 ? '' : 's'} merged`);
    if (r.reroutedLinks) parts.push(`${r.reroutedLinks} link${r.reroutedLinks === 1 ? '' : 's'} re-routed`);
    return parts.join(', ');
  }

  const api = { tidy, summary, MERGE_RADIUS, SNAP_RADIUS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.RouteTidy = api;
})(typeof self !== 'undefined' ? self : this);
