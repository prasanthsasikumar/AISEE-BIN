// AISEE-BIN map editor. Vanilla JS, talks to the shared Supabase REST + Storage API.
'use strict';

// Supabase Cloud, project djfpemdkeguztyuerxqc (ap-southeast-1). Moved off the
// self-hosted VPS on 2026-09-09; storage here is CDN-fronted, so the point cloud
// loads in seconds rather than minutes.
const SUPABASE_URL = 'https://djfpemdkeguztyuerxqc.supabase.co';
const SUPABASE_KEY = 'sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL';
const BUCKET = 'aiseebin-maps';
const CATEGORY_COLORS = { destination: '#2f80ed', junction: '#9aa0a6', exhibit: '#27ae60', hazard: '#eb5757' };

// ---------- state ----------
const state = {
  slug: 'default',
  versions: [],
  current: null,          // loaded version row
  graph: null,            // editable copy of graph JSON
  points: null,           // Float32Array xyz
  pendingPoints: null,    // Float32Array xyz not yet in storage (an Immersal import); uploaded with the next save
  heights: null,          // {min,max,med,lo,hi} percentiles of point y, for the Scan view band
  band: null,             // {lo,hi} height band drawn, or null for everything
  density: false,         // draw points as soft blobs so clusters read as shapes
  pointsBitmap: null,     // offscreen canvas cache of the point cloud
  pointsBitmapMeta: null, // {minX,minZ,scale}
  mode: 'select',
  selectedNode: null,
  selectedEdge: null,     // index into graph.edges
  connectFrom: null,
  pathFrom: null,         // last node of the path being drawn
  dirty: false,
  view: { scale: 40, ox: 0, oy: 0 },  // px per metre, screen offset of world origin
  drag: null,
  clouds: new Map(),      // Immersal map id -> {id, raw, disp, match, centre, color, hidden}; placements live in graph.immersalAlignment.maps
  selectedCloud: null,    // Immersal map id of the scan being lined up
  history: [],            // graph snapshots for undo
  future: [],             // graph snapshots for redo
};

// ---------- undo / redo ----------
const snapshot = () => JSON.stringify(state.graph);

/// Call BEFORE mutating the graph. Coalesces identical consecutive snapshots.
function beginChange() {
  if (!state.graph) return;
  const snap = snapshot();
  if (state.history[state.history.length - 1] === snap) return;
  state.history.push(snap);
  if (state.history.length > 200) state.history.shift();
  state.future = [];
  updateUndoButtons();
}

function restore(snap) {
  const selectedId = state.selectedNode?.id;
  state.graph = JSON.parse(snap);
  state.selectedNode = selectedId ? nodeById(selectedId) : null;
  state.selectedEdge = null; state.connectFrom = null; state.pathFrom = null;
  state.dirty = true;
  updateSaveButton(); updateUndoButtons(); renderSidebar(); draw();
}

function undo() {
  if (!state.history.length) return;
  state.future.push(snapshot());
  restore(state.history.pop());
  setStatus('Undid last change.');
}

function redo() {
  if (!state.future.length) return;
  state.history.push(snapshot());
  restore(state.future.pop());
  setStatus('Redid change.');
}

function updateUndoButtons() {
  $('undo').disabled = !state.history.length;
  $('redo').disabled = !state.future.length;
}

const $ = id => document.getElementById(id);
const canvas = $('canvas');
const ctx = canvas.getContext('2d');

// ---------- Supabase helpers ----------
const headers = { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` };

async function rest(path, options = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...options,
    headers: { ...headers, 'Content-Type': 'application/json', ...(options.headers || {}) },
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.status === 204 ? null : res.json();
}

function publicURL(path) { return `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${path}`; }

/// Puts one blob into the maps bucket. Paths embed the version, so nothing is
/// ever overwritten; the bucket's insert policy lets the publishable key do this.
async function uploadObject(path, body, contentType = 'application/octet-stream') {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET}/${path}`, {
    method: 'POST', headers: { ...headers, 'Content-Type': contentType, 'x-upsert': 'false' }, body,
  });
  if (!res.ok) throw new Error(`upload ${path}: ${res.status} ${await res.text()}`);
}

/// Fetches a storage object, inflating it when the path says it is gzipped.
/// The app uploads blobs compressed (roughly half the bytes over a slow link);
/// objects published before that are still stored plain, so both must work.
async function fetchMaybeGzipped(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  if (!url.endsWith('.gz')) return res.arrayBuffer();
  const inflated = res.body.pipeThrough(new DecompressionStream('gzip'));
  return new Response(inflated).arrayBuffer();
}

const NEW_MAP = '__new__';

/// Fills the Map dropdown with every slug that has at least one version, labelled
/// by the map's name (`graph.name`) from its newest version. The slug stays the
/// option's value: it is the server key, while the name is what people call it.
async function loadSlugs() {
  const rows = await rest('ab_map_versions?select=map_slug,version,name:graph->>name&order=map_slug.asc,version.desc');
  const names = new Map();   // slug -> name from its highest version
  for (const r of rows) if (!names.has(r.map_slug)) names.set(r.map_slug, r.name || null);
  if (!names.has(state.slug)) names.set(state.slug, state.graph?.name ?? null);
  const sel = $('slug'); sel.innerHTML = '';
  [...names.keys()].sort().forEach(slug => {
    const o = document.createElement('option');
    o.value = slug;
    const name = names.get(slug);
    // Show the slug too when it differs, so the server key stays discoverable.
    o.textContent = !name ? slug : (name.toLowerCase() === slug ? name : `${name} (${slug})`);
    sel.appendChild(o);
  });
  const o = document.createElement('option'); o.value = NEW_MAP; o.textContent = '+ New map…'; sel.appendChild(o);
  sel.value = state.slug;
}

async function loadVersions() {
  setStatus('Loading versions…');
  // `node_count` is a computed column (see server/schema.sql): it gives the sidebar
  // its "N nodes" without dragging every version's whole graph across the wire.
  state.versions = await rest(`ab_map_versions?map_slug=eq.${encodeURIComponent(state.slug)}&select=id,version,source,note,point_count,created_at,worldmap_path,pointcloud_path,node_count&order=version.desc`);
  renderVersions();
  setStatus(state.versions.length ? `${state.versions.length} version(s).` : 'No versions yet. Upload one from the app in Authoring mode.');
  if (state.versions.length && !state.current) await loadVersion(state.versions[0]);
}

async function loadVersion(row) {
  if (state.dirty && !confirm('Discard unsaved changes?')) return;
  // The version list is fetched without `graph`, so pull it for the one being opened.
  if (!row.graph) {
    setStatus(`Loading v${row.version}…`);
    const [full] = await rest(`ab_map_versions?id=eq.${encodeURIComponent(row.id)}&select=graph`);
    if (!full) { setStatus(`Version ${row.version} has gone missing.`, true); return; }
    row.graph = full.graph;
  }
  state.current = row;
  state.graph = JSON.parse(JSON.stringify(row.graph));
  state.graph.pois ??= []; state.graph.edges ??= [];
  state.selectedNode = state.selectedEdge = state.connectFrom = null;
  state.dirty = false;
  state.history = []; state.future = []; updateUndoButtons();
  state.points = null; state.pointsBitmap = null; state.heights = null; renderScanTools();
  renderVersions(); renderSidebar(); updateSaveButton();
  $('downloadWorldMap').href = row.worldmap_path ? publicURL(row.worldmap_path) : '#';
  $('downloadPoints').href = row.pointcloud_path ? publicURL(row.pointcloud_path) : '#';
  $('versionInfo').textContent = `v${row.version} · ${row.source} · ${new Date(row.created_at).toLocaleString()}${row.note ? ' · ' + row.note : ''}`;
  fitView(); draw();
  state.clouds = new Map(); state.selectedCloud = null; renderClouds();
  if (alignmentMaps()) loadClouds().then(() => { fitView(); draw(); });
  if (row.pointcloud_path) {
    setStatus(`Loading ${row.point_count ?? ''} points…`);
    try {
      const buf = await fetchMaybeGzipped(publicURL(row.pointcloud_path));
      state.points = new Float32Array(buf);
      computeHeights(); renderScanTools(); buildPointsBitmap();
      setStatus(`Loaded v${row.version}: ${state.graph.pois.length} nodes, ${state.graph.edges.length} edges, ${state.points.length / 3} points.`);
    } catch (e) { setStatus(`Point cloud failed: ${e.message}`, true); }
    fitView(); draw();
  }
}

async function saveVersion() {
  if (!state.graph) return;
  const isolated = renderConnectivity();
  if (isolated.length && !confirm(`${isolated.length} place(s) are not connected to the route network (${isolated.map(p => p.name).join(', ')}).\nGuidance will not be able to reach them. Save anyway?`)) return;
  const btn = $('save'); btn.disabled = true;
  try {
    setStatus('Saving…');
    const version = await rest('rpc/ab_next_version', { method: 'POST', body: JSON.stringify({ slug: state.slug }) });
    let pointcloudPath = state.current?.pointcloud_path ?? null, pointCount = state.current?.point_count ?? null;
    if (state.pendingPoints) {
      // Same layout the app uses, minus gzip: the cloud is small and the browser
      // has no cheap way to compress a Float32Array.
      pointcloudPath = `${state.slug}/v${version}/points.f32`;
      pointCount = state.pendingPoints.length / 3;
      setStatus(`Uploading ${pointCount} points…`);
      await uploadObject(pointcloudPath, state.pendingPoints);
    }
    const row = {
      map_slug: state.slug, version, source: 'web', note: $('note').value || null,
      graph: state.graph,
      worldmap_path: state.current?.worldmap_path ?? null,
      pointcloud_path: pointcloudPath,
      point_count: pointCount,
    };
    const [saved] = await rest('ab_map_versions', { method: 'POST', body: JSON.stringify(row), headers: { Prefer: 'return=representation' } });
    state.pendingPoints = null;
    state.dirty = false; $('note').value = '';
    state.current = saved;
    await loadSlugs();      // a renamed map relabels its dropdown entry
    await loadVersions();
    renderVersions();
    setStatus(`Saved as v${saved.version}. The app fetches it on next launch.`);
  } catch (e) { setStatus(`Save failed: ${e.message}`, true); }
  updateSaveButton();
}

// ---------- geometry ----------
const toScreen = (x, z) => [state.view.ox + x * state.view.scale, state.view.oy + z * state.view.scale];
const toWorld = (sx, sy) => [(sx - state.view.ox) / state.view.scale, (sy - state.view.oy) / state.view.scale];
const nodeById = id => state.graph?.pois.find(p => p.id === id);
const dist = (a, b, c, d) => Math.hypot(a - c, b - d);

function pointToSegment(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
  const t = l2 ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) : 0;
  return dist(px, py, ax + dx * t, ay + dy * t);
}

function hitNode(sx, sy) {
  if (!state.graph) return null;
  for (let i = state.graph.pois.length - 1; i >= 0; i--) {
    const p = state.graph.pois[i]; const [x, y] = toScreen(p.x, p.z);
    if (dist(sx, sy, x, y) <= 11) return p;
  }
  return null;
}

function hitEdge(sx, sy) {
  if (!state.graph) return null;
  for (let i = 0; i < state.graph.edges.length; i++) {
    const e = state.graph.edges[i]; const a = nodeById(e.from), b = nodeById(e.to);
    if (!a || !b) continue;
    const [ax, ay] = toScreen(a.x, a.z), [bx, by] = toScreen(b.x, b.z);
    if (pointToSegment(sx, sy, ax, ay, bx, by) <= 6) return i;
  }
  return null;
}

function contentBounds(trim = false) {
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  const add = (x, z) => { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minZ = Math.min(minZ, z); maxZ = Math.max(maxZ, z); };
  state.graph?.pois.forEach(p => add(p.x, p.z));
  if (hasClouds()) {
    for (const cl of state.clouds.values()) {
      const pl = placementOf(cl.id); if (!pl) continue;
      for (let i = 0; i < cl.disp.length; i += 30) { const [x, , z] = CloudAlign.apply(pl, cl.disp[i], cl.disp[i + 1], cl.disp[i + 2]); add(x, z); }
    }
  } else if (state.points) {
    if (trim) {
      // Ignore stray far-away feature points when fitting the view (2nd..98th percentile).
      const xs = [], zs = [];
      const stride = Math.max(3, Math.floor(state.points.length / 3 / 20000) * 3);
      for (let i = 0; i < state.points.length; i += stride) { xs.push(state.points[i]); zs.push(state.points[i + 2]); }
      xs.sort((a, b) => a - b); zs.sort((a, b) => a - b);
      const lo = Math.floor(xs.length * 0.02), hi = Math.ceil(xs.length * 0.98) - 1;
      add(xs[lo], zs[lo]); add(xs[hi], zs[hi]);
    } else {
      for (let i = 0; i < state.points.length; i += 3) add(state.points[i], state.points[i + 2]);
    }
  }
  if (minX === Infinity) { add(-5, -5); add(5, 5); }
  return { minX, maxX, minZ, maxZ };
}

function fitView() {
  const b = contentBounds(true), w = canvas.clientWidth, h = canvas.clientHeight;
  const spanX = Math.max(2, b.maxX - b.minX), spanZ = Math.max(2, b.maxZ - b.minZ);
  state.view.scale = Math.max(4, Math.min(120, 0.9 * Math.min(w / spanX, h / spanZ)));
  state.view.ox = w / 2 - ((b.minX + b.maxX) / 2) * state.view.scale;
  state.view.oy = h / 2 - ((b.minZ + b.maxZ) / 2) * state.view.scale;
}

// ---------- point cloud cache ----------
/// Percentiles of point height, computed once per cloud: the colour ramp uses
/// 5–95%, the Scan view sliders span 1–99%, and "floor" is the median band.
function computeHeights() {
  const pts = state.points; if (!pts || !pts.length) { state.heights = null; return; }
  const n = pts.length / 3, step = Math.max(1, Math.floor(n / 40000));
  const ys = []; for (let i = 0; i < n; i += step) ys.push(pts[i * 3 + 1]);
  ys.sort((a, c) => a - c); const q = f => ys[Math.min(ys.length - 1, Math.floor(ys.length * f))];
  state.heights = { min: q(0.01), max: q(0.99), med: q(0.5), lo: q(0.05), hi: q(0.95) };
}

function inBand(y) { return !state.band || (y >= state.band.lo && y <= state.band.hi); }

function buildPointsBitmap() {
  const pts = state.points; if (!pts || !pts.length) return;
  if (!state.heights) computeHeights();
  const b = contentBounds(); const scale = 25; // px per metre in the cache
  const w = Math.ceil((b.maxX - b.minX) * scale) + 2, h = Math.ceil((b.maxZ - b.minZ) * scale) + 2;
  if (w * h > 40e6) { setStatus('Point cloud too large to cache; drawing directly.'); return; }
  const off = document.createElement('canvas'); off.width = w; off.height = h;
  const octx = off.getContext('2d');
  const { lo, hi } = state.heights;
  if (state.density) {
    // Soft blobs accumulate where features cluster, so furniture, textured
    // walls and floor pattern read as solid shapes instead of specks.
    octx.globalAlpha = 0.10; octx.fillStyle = '#9db4ff'; const r = 0.22 * scale;
    for (let i = 0; i < pts.length; i += 3) {
      if (!inBand(pts[i + 1])) continue;
      const px = (pts[i] - b.minX) * scale, py = (pts[i + 2] - b.minZ) * scale;
      if (px < -r || py < -r || px >= w + r || py >= h + r) continue;
      octx.beginPath(); octx.arc(px, py, r, 0, 6.2832); octx.fill();
    }
  } else {
    const img = octx.createImageData(w, h); const d = img.data;
    for (let i = 0; i < pts.length; i += 3) {
      if (!inBand(pts[i + 1])) continue;
      const px = Math.floor((pts[i] - b.minX) * scale), py = Math.floor((pts[i + 2] - b.minZ) * scale);
      if (px < 0 || py < 0 || px >= w || py >= h) continue;
      const t = Math.max(0, Math.min(1, (pts[i + 1] - lo) / (hi - lo || 1)));
      const k = (py * w + px) * 4;
      d[k] = 60 + 190 * t; d[k + 1] = 110 + 100 * t; d[k + 2] = 230 - 190 * t; d[k + 3] = Math.min(255, d[k + 3] + 110);
    }
    octx.putImageData(img, 0, 0);
  }
  state.pointsBitmap = off; state.pointsBitmapMeta = { minX: b.minX, minZ: b.minZ, scale };
}

// ---------- drawing ----------
function resize() {
  const dpr = window.devicePixelRatio || 1;
  canvas.width = canvas.clientWidth * dpr; canvas.height = canvas.clientHeight * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  draw();
}

function draw() {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  ctx.clearRect(0, 0, w, h);
  drawGrid(w, h);
  if ($('showPoints').checked) drawPoints();
  if (!state.graph) return;
  const showLabels = $('showLabels').checked;

  // edges
  state.graph.edges.forEach((e, i) => {
    const a = nodeById(e.from), b = nodeById(e.to); if (!a || !b) return;
    const [ax, ay] = toScreen(a.x, a.z), [bx, by] = toScreen(b.x, b.z);
    ctx.strokeStyle = i === state.selectedEdge ? '#ffd166' : 'rgba(230,232,238,.55)';
    ctx.lineWidth = i === state.selectedEdge ? 4 : 2.5;
    ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.stroke();
    if (showLabels) {
      const len = Math.hypot(a.x - b.x, a.z - b.z).toFixed(1);
      ctx.fillStyle = 'rgba(230,232,238,.6)'; ctx.font = '11px ui-monospace, monospace';
      ctx.fillText(`${len} m`, (ax + bx) / 2 + 4, (ay + by) / 2 - 4);
    }
  });

  // origin + forward arrow
  const [ox, oy] = toScreen(0, 0);
  ctx.strokeStyle = 'rgba(255,255,255,.35)'; ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.moveTo(ox - 8, oy); ctx.lineTo(ox + 8, oy); ctx.moveTo(ox, oy + 8); ctx.lineTo(ox, oy - 18); ctx.stroke();

  // nodes
  const isolatedIds = new Set(isolatedPlaces().map(p => p.id));
  state.graph.pois.forEach(p => {
    const [x, y] = toScreen(p.x, p.z);
    const r = p.category === 'junction' ? 6 : 8;
    if (isolatedIds.has(p.id)) {
      ctx.beginPath(); ctx.arc(x, y, r + 6, 0, Math.PI * 2);
      ctx.strokeStyle = '#f2c14e'; ctx.lineWidth = 2; ctx.setLineDash([3, 3]); ctx.stroke(); ctx.setLineDash([]);
    }
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = CATEGORY_COLORS[p.category] || CATEGORY_COLORS.destination; ctx.fill();
    if (p === state.selectedNode || p === state.connectFrom || p === state.pathFrom) {
      ctx.strokeStyle = (p === state.connectFrom || p === state.pathFrom) ? '#ffd166' : '#fff'; ctx.lineWidth = 3; ctx.stroke();
    }
    const radius = announceRadius(p);
    if (radius > 0) {
      const selected = p === state.selectedNode;
      ctx.beginPath(); ctx.arc(x, y, radius * state.view.scale, 0, Math.PI * 2);
      ctx.strokeStyle = (CATEGORY_COLORS[p.category]) + (selected ? 'cc' : '55'); ctx.lineWidth = selected ? 2 : 1;
      ctx.setLineDash([4, 4]); ctx.stroke(); ctx.setLineDash([]);
    }
    if (showLabels) {
      ctx.font = '12px -apple-system, sans-serif'; ctx.fillStyle = '#e6e8ee';
      ctx.fillText(p.name, x + r + 4, y + 4);
    }
  });
}

function drawGrid(w, h) {
  const s = state.view.scale; const step = s < 12 ? 5 : 1;
  const [x0, z0] = toWorld(0, 0), [x1, z1] = toWorld(w, h);
  ctx.lineWidth = 1; ctx.font = '10px ui-monospace, monospace'; ctx.fillStyle = 'rgba(138,145,158,.7)';
  for (let x = Math.floor(x0 / step) * step; x <= x1; x += step) {
    const [sx] = toScreen(x, 0); ctx.strokeStyle = x % 5 === 0 ? 'rgba(255,255,255,.14)' : 'rgba(255,255,255,.05)';
    ctx.beginPath(); ctx.moveTo(sx, 0); ctx.lineTo(sx, h); ctx.stroke();
    if (x % 5 === 0) ctx.fillText(`x ${x}`, sx + 2, 10);
  }
  for (let z = Math.floor(z0 / step) * step; z <= z1; z += step) {
    const [, sy] = toScreen(0, z); ctx.strokeStyle = z % 5 === 0 ? 'rgba(255,255,255,.14)' : 'rgba(255,255,255,.05)';
    ctx.beginPath(); ctx.moveTo(0, sy); ctx.lineTo(w, sy); ctx.stroke();
    if (z % 5 === 0) ctx.fillText(`z ${z}`, 2, sy - 2);
  }
}

function drawPoints() {
  if (hasClouds()) { drawClouds(); return; }
  if (state.pointsBitmap) {
    const m = state.pointsBitmapMeta; const [sx, sy] = toScreen(m.minX, m.minZ);
    const k = state.view.scale / m.scale;
    ctx.imageSmoothingEnabled = k < 1;
    ctx.drawImage(state.pointsBitmap, sx, sy, state.pointsBitmap.width * k, state.pointsBitmap.height * k);
  } else if (state.points) {
    ctx.fillStyle = 'rgba(120,160,255,.5)';
    const stride = Math.max(3, Math.floor(state.points.length / 3 / 60000) * 3);
    for (let i = 0; i < state.points.length; i += stride) {
      if (!inBand(state.points[i + 1])) continue;
      const [x, y] = toScreen(state.points[i], state.points[i + 2]); ctx.fillRect(x, y, 1.5, 1.5);
    }
  }
}

// ---------- connectivity ----------
/// Named places (non-junctions) that cannot be reached from the largest connected group.
function isolatedPlaces() {
  const g = state.graph; if (!g || !g.pois.length) return [];
  const adj = new Map(g.pois.map(p => [p.id, new Set()]));
  g.edges.forEach(e => { if (adj.has(e.from) && adj.has(e.to)) { adj.get(e.from).add(e.to); adj.get(e.to).add(e.from); } });
  const seen = new Set(); const groups = [];
  for (const p of g.pois) {
    if (seen.has(p.id)) continue;
    const group = new Set(); const stack = [p.id];
    while (stack.length) { const n = stack.pop(); if (group.has(n)) continue; group.add(n); seen.add(n); adj.get(n).forEach(m => stack.push(m)); }
    groups.push(group);
  }
  const named = id => nodeById(id)?.category !== 'junction';
  const main = groups.reduce((a, b) => ([...b].filter(named).length > [...a].filter(named).length ? b : a), groups[0]);
  return g.pois.filter(p => named(p.id) && !main.has(p.id));
}

function renderConnectivity() {
  const isolated = isolatedPlaces();
  const box = $('connectivity'), btn = $('autoConnect');
  box.hidden = btn.hidden = isolated.length === 0;
  if (isolated.length) {
    box.textContent = `⚠ ${isolated.length} place${isolated.length > 1 ? 's' : ''} not connected to the route network: ${isolated.map(p => p.name).join(', ')}. Guidance cannot reach them.`;
  }
  return isolated;
}

/// Connects each isolated place to its nearest other node.
function autoConnectIsolated() {
  const isolated = isolatedPlaces(); if (!isolated.length) return;
  beginChange();
  isolated.forEach(p => {
    const others = state.graph.pois.filter(q => q.id !== p.id);
    const nearest = others.reduce((a, q) => Math.hypot(q.x - p.x, q.z - p.z) < Math.hypot(a.x - p.x, a.z - p.z) ? q : a, others[0]);
    if (nearest) state.graph.edges.push({ from: p.id, to: nearest.id });
  });
  markDirty();
  setStatus(`Connected ${isolated.length} place(s) to the nearest node. Check the new edges, then save.`);
}

// ---------- sidebar ----------
function renderVersions() {
  const ul = $('versions'); ul.innerHTML = '';
  if (!state.versions.length) { ul.innerHTML = '<li class="muted">No versions yet.</li>'; return; }
  state.versions.forEach(v => {
    const li = document.createElement('li');
    li.className = state.current?.id === v.id ? 'active' : '';
    li.innerHTML = `<strong>v${v.version}</strong> <span class="muted">${v.source}</span><span class="meta">${new Date(v.created_at).toLocaleString()}${v.note ? ' · ' + escapeHTML(v.note) : ''}<br>${v.node_count ?? v.graph?.pois?.length ?? 0} nodes · ${v.point_count ?? 0} pts</span>`;
    li.onclick = () => loadVersion(v);
    ul.appendChild(li);
  });
}

// Announce radius, metres: exhibits and hazards are spoken when a visitor comes
// this close. Matches NavigationPOI.announceRadius in the iOS app, which ignores
// values outside 0.5–20 m and falls back to the default.
const DEFAULT_ANNOUNCE_RADIUS = 2.5;
const ANNOUNCE_RADIUS_MIN = 0.5, ANNOUNCE_RADIUS_MAX = 20;
function isAnnounced(p) { return p.category === 'exhibit' || p.category === 'hazard'; }
function announceRadius(p) {
  if (!isAnnounced(p)) return 0;
  const r = p.announceRadius;
  return typeof r === 'number' && r >= ANNOUNCE_RADIUS_MIN && r <= ANNOUNCE_RADIUS_MAX ? r : DEFAULT_ANNOUNCE_RADIUS;
}
function renderRadius(n) {
  $('nodeRadiusRow').hidden = !isAnnounced(n);
  const r = announceRadius(n) || DEFAULT_ANNOUNCE_RADIUS;
  $('nodeRadiusRange').value = Math.min(r, +$('nodeRadiusRange').max);
  if (document.activeElement !== $('nodeRadius')) $('nodeRadius').value = r;
  $('nodeRadiusValue').textContent = `${r} m${typeof n.announceRadius === 'number' ? '' : ' (default)'}`;
  $('nodeRadiusReset').hidden = typeof n.announceRadius !== 'number';
}
function setRadius(n, value) {
  const v = Math.round(parseFloat(value) * 100) / 100;
  if (isNaN(v)) return;
  n.announceRadius = Math.min(ANNOUNCE_RADIUS_MAX, Math.max(ANNOUNCE_RADIUS_MIN, v));
}

function renderSidebar() {
  const g = state.graph;
  $('mapName').value = g?.name ?? '';
  $('mapStats').textContent = g ? `${g.pois.length} nodes · ${g.edges.length} edges` : '';
  renderConnectivity();
  const n = state.selectedNode;
  $('nodePanel').hidden = !n;
  if (n) {
    $('nodeId').textContent = n.id; $('nodeName').value = n.name; $('nodeCategory').value = n.category || 'destination';
    $('nodeDetails').value = n.details || ''; $('nodeAliases').value = (n.aliases || []).join(', ');
    $('nodeX').value = n.x.toFixed(2); $('nodeZ').value = n.z.toFixed(2);
    renderRadius(n);
    const neighbours = g.edges.filter(e => e.from === n.id || e.to === n.id).map(e => nodeById(e.from === n.id ? e.to : e.from)?.name ?? '?');
    $('nodeEdges').textContent = neighbours.join(', ') || 'none';
  }
  const ei = state.selectedEdge;
  $('edgePanel').hidden = ei === null;
  if (ei !== null) {
    const e = g.edges[ei], a = nodeById(e.from), b = nodeById(e.to);
    $('edgeLabel').textContent = `${a?.name ?? e.from} ↔ ${b?.name ?? e.to}`;
    $('edgeLength').textContent = a && b ? `${Math.hypot(a.x - b.x, a.z - b.z).toFixed(2)} m` : '';
  }
  renderClouds();
}

function markDirty() { state.dirty = true; updateSaveButton(); renderSidebar(); draw(); }
function updateSaveButton() { $('save').disabled = !state.graph; $('save').textContent = state.dirty ? 'Save as new version *' : 'Save as new version'; }
function setStatus(text, isError = false) { const f = $('status'); f.textContent = text; f.className = isError ? 'error' : ''; }
function escapeHTML(s) { return s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

function selectNode(n) { state.selectedNode = n; state.selectedEdge = null; renderSidebar(); draw(); }
function selectEdge(i) { state.selectedEdge = i; state.selectedNode = null; renderSidebar(); draw(); }

function setMode(mode) {
  state.mode = mode; state.connectFrom = null;
  state.pathFrom = mode === 'path' ? state.selectedNode : null;
  document.querySelectorAll('button.mode').forEach(b => b.classList.toggle('active', b.id === { select: 'modeSelect', add: 'modeAdd', connect: 'modeConnect', path: 'modePath', cloud: 'moveCloud' }[mode]));
  canvas.className = mode === 'select' ? '' : mode === 'cloud' ? 'dragging' : mode;
  $('hint').textContent = { select: 'Drag to pan · wheel to zoom · drag a node to move it · Delete removes the selection',
    add: 'Click on the canvas to place a node', connect: 'Click a node, then another node, to add (or remove) an edge',
    path: (state.pathFrom ? `Path from "${state.pathFrom.name}": ` : 'Path: click a node to start, then ') + 'click along the corridor to lay waypoints · click a node to end there · Esc to stop',
    cloud: 'Drag to move the selected scan · Alt/Option-drag to turn it · arrows nudge 10 cm (Shift 1 m) · [ ] turn 1° (Shift 5°) · Esc to stop' }[mode];
  draw();
}

function addWaypointAt(x, z) {
  beginChange();
  const n = state.graph.pois.filter(p => p.category === 'junction').length + 1;
  const node = { id: uniqueId(`wp-${n}`), name: `Waypoint ${n}`, x: +x.toFixed(2), z: +z.toFixed(2), category: 'junction', details: null, aliases: [] };
  state.graph.pois.push(node);
  return node;
}

function uniqueId(base) {
  const slug = base.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'node';
  let id = slug, n = 2; while (nodeById(id)) id = `${slug}-${n++}`; return id;
}

function addNodeAt(x, z) {
  beginChange();
  const node = { id: uniqueId('node'), name: `Node ${state.graph.pois.length + 1}`, x: +x.toFixed(2), z: +z.toFixed(2), category: 'destination', details: null, aliases: [] };
  state.graph.pois.push(node); selectNode(node); markDirty(); setMode('select'); $('nodeName').focus(); $('nodeName').select();
}

function handlePathClick(node, sx, sy) {
  if (node) {
    if (state.pathFrom && state.pathFrom !== node) toggleEdgeEnsure(state.pathFrom, node);
    state.pathFrom = node; selectNode(node); setModeHint();
  } else {
    const [x, z] = toWorld(sx, sy); const wp = addWaypointAt(x, z);
    if (state.pathFrom) toggleEdgeEnsure(state.pathFrom, wp);
    else setStatus('Path started on empty canvas: remember to end it on a place, or it stays disconnected.', false);
    state.pathFrom = wp; selectNode(wp); markDirty(); setModeHint();
  }
}

function setModeHint() { if (state.mode === 'path') $('hint').textContent = `Path from "${state.pathFrom?.name ?? '?'}": click along the corridor to lay waypoints · click a node to end there · Esc to stop`; }

/// Adds the edge if it does not exist (never removes).
function toggleEdgeEnsure(a, b) {
  if (a.id === b.id) return;
  const exists = state.graph.edges.some(e => (e.from === a.id && e.to === b.id) || (e.from === b.id && e.to === a.id));
  if (!exists) { beginChange(); state.graph.edges.push({ from: a.id, to: b.id }); markDirty(); }
}

function toggleEdge(a, b) {
  if (a.id === b.id) return;
  beginChange();
  const i = state.graph.edges.findIndex(e => (e.from === a.id && e.to === b.id) || (e.from === b.id && e.to === a.id));
  if (i >= 0) state.graph.edges.splice(i, 1); else state.graph.edges.push({ from: a.id, to: b.id });
  markDirty();
}

// ---------- events ----------
canvas.addEventListener('pointerdown', ev => {
  const r = canvas.getBoundingClientRect(); const sx = ev.clientX - r.left, sy = ev.clientY - r.top;
  canvas.setPointerCapture(ev.pointerId);
  if (ev.button === 1 || ev.button === 2 || ev.shiftKey) {
    // Middle / right / shift-drag pans regardless of the editing mode.
    ev.preventDefault();
    state.drag = { type: 'pan', x: sx, y: sy, ox: state.view.ox, oy: state.view.oy };
    canvas.classList.add('dragging');
    return;
  }
  if (ev.button !== 0) return;
  if (state.mode === 'cloud') {
    const pl = placementOf(state.selectedCloud); if (!pl) return;
    const [wx, wz] = toWorld(sx, sy);
    state.drag = { type: 'cloud', wx, wz, orig: { ...pl }, rotate: ev.altKey, snap: snapshot(), moved: false };
    return;
  }
  const node = hitNode(sx, sy);
  if (state.mode === 'add') { if (!node) { const [x, z] = toWorld(sx, sy); addNodeAt(x, z); } return; }
  if (state.mode === 'path') {
    // Snap to an existing node within 1 m so waypoints laid next to a place attach to it.
    if (!node) {
      const [wx, wz] = toWorld(sx, sy);
      const near = state.graph.pois.filter(p => Math.hypot(p.x - wx, p.z - wz) <= 1.0)
        .sort((a, b) => Math.hypot(a.x - wx, a.z - wz) - Math.hypot(b.x - wx, b.z - wz))[0];
      if (near) return handlePathClick(near, sx, sy);
    }
    return handlePathClick(node, sx, sy);
  }
  if (state.mode === 'connect') {
    if (!node) return;
    if (!state.connectFrom) { state.connectFrom = node; draw(); }
    else { toggleEdge(state.connectFrom, node); state.connectFrom = null; }
    return;
  }
  if (node) { selectNode(node); state.drag = { type: 'node', node, moved: false, snap: snapshot() }; return; }
  const edge = hitEdge(sx, sy);
  if (edge !== null) { selectEdge(edge); return; }
  state.drag = { type: 'pan', x: sx, y: sy, ox: state.view.ox, oy: state.view.oy };
  canvas.classList.add('dragging');
});

canvas.addEventListener('pointermove', ev => {
  const r = canvas.getBoundingClientRect(); const sx = ev.clientX - r.left, sy = ev.clientY - r.top;
  const [wx, wz] = toWorld(sx, sy); $('coords').textContent = `x ${wx.toFixed(2)}  z ${wz.toFixed(2)}`;
  if (!state.drag) return;
  if (state.drag.type === 'pan') { state.view.ox = state.drag.ox + sx - state.drag.x; state.view.oy = state.drag.oy + sy - state.drag.y; draw(); }
  else if (state.drag.type === 'cloud') { dragCloud(wx, wz); }
  else { state.drag.node.x = +wx.toFixed(2); state.drag.node.z = +wz.toFixed(2); state.drag.moved = true; renderSidebar(); draw(); }
});

canvas.addEventListener('pointerup', () => {
  if ((state.drag?.type === 'node' || state.drag?.type === 'cloud') && state.drag.moved) {
    // Record the pre-drag state as one undo step.
    state.history.push(state.drag.snap); if (state.history.length > 200) state.history.shift();
    state.future = []; updateUndoButtons();
    markDirty();
  }
  const wasCloud = state.drag?.type === 'cloud';
  state.drag = null; if (state.mode !== 'cloud') canvas.classList.remove('dragging');
  if (wasCloud) { renderCloudEdit(); scheduleOverlap(); }
});

canvas.addEventListener('contextmenu', ev => ev.preventDefault());
canvas.addEventListener('auxclick', ev => ev.preventDefault());

canvas.addEventListener('wheel', ev => {
  ev.preventDefault();
  const r = canvas.getBoundingClientRect(); const sx = ev.clientX - r.left, sy = ev.clientY - r.top;
  const [wx, wz] = toWorld(sx, sy);
  state.view.scale = Math.max(3, Math.min(300, state.view.scale * (ev.deltaY < 0 ? 1.12 : 1 / 1.12)));
  state.view.ox = sx - wx * state.view.scale; state.view.oy = sy - wz * state.view.scale;
  draw();
}, { passive: false });

document.addEventListener('keydown', ev => {
  const mod = ev.metaKey || ev.ctrlKey;
  if (mod && ev.key.toLowerCase() === 'z' && !['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) {
    ev.preventDefault(); ev.shiftKey ? redo() : undo(); return;
  }
  if (mod && ev.key.toLowerCase() === 'y') { ev.preventDefault(); redo(); return; }
  if (['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement.tagName)) return;
  if (state.mode === 'cloud' && placementOf(state.selectedCloud)) {
    const m = ev.shiftKey ? 1 : 0.1, deg = ev.shiftKey ? 5 : 1;
    const moves = { ArrowLeft: [-m, 0, 0], ArrowRight: [m, 0, 0], ArrowUp: [0, -m, 0], ArrowDown: [0, m, 0], '[': [0, 0, -deg], ']': [0, 0, deg], '{': [0, 0, -deg], '}': [0, 0, deg] };
    const mv = moves[ev.key];
    if (mv) { ev.preventDefault(); nudgeCloud(mv[0], mv[1], mv[2]); return; }
  }
  if (ev.key === 'Escape') { setMode('select'); selectNode(null); }
  if (ev.key === 'Delete' || ev.key === 'Backspace') { if (state.selectedNode) deleteNode(); else if (state.selectedEdge !== null) deleteEdge(); }
});

function deleteNode() {
  const n = state.selectedNode; if (!n || !confirm(`Delete "${n.name}" and its edges?`)) return;
  beginChange();
  state.graph.pois = state.graph.pois.filter(p => p !== n);
  state.graph.edges = state.graph.edges.filter(e => e.from !== n.id && e.to !== n.id);
  state.selectedNode = null; markDirty();
}
function deleteEdge() { if (state.selectedEdge === null) return; beginChange(); state.graph.edges.splice(state.selectedEdge, 1); state.selectedEdge = null; markDirty(); }

// node panel bindings
['nodeName', 'nodeCategory', 'nodeDetails', 'nodeAliases', 'nodeX', 'nodeZ', 'nodeRadius', 'nodeRadiusRange', 'mapName'].forEach(id => $(id).addEventListener('focus', beginChange));
const bindNode = (id, apply) => $(id).addEventListener('input', () => { if (!state.selectedNode) return; apply(state.selectedNode, $(id).value); state.dirty = true; updateSaveButton(); $('mapStats').textContent = `${state.graph.pois.length} nodes · ${state.graph.edges.length} edges`; draw(); });
bindNode('nodeName', (n, v) => n.name = v);
bindNode('nodeCategory', (n, v) => { n.category = v; renderRadius(n); });
bindNode('nodeRadius', (n, v) => { setRadius(n, v); renderRadius(n); });
bindNode('nodeRadiusRange', (n, v) => { setRadius(n, v); renderRadius(n); });
// The slider can be dragged without focusing first; snapshot for undo on press.
$('nodeRadiusRange').addEventListener('pointerdown', beginChange);
$('nodeRadius').addEventListener('change', () => { if (state.selectedNode) renderRadius(state.selectedNode); });
$('nodeRadiusReset').onclick = () => {
  const n = state.selectedNode; if (!n) return;
  beginChange(); delete n.announceRadius; markDirty();
};
bindNode('nodeDetails', (n, v) => n.details = v || null);
bindNode('nodeAliases', (n, v) => n.aliases = v.split(',').map(s => s.trim()).filter(Boolean));
bindNode('nodeX', (n, v) => { if (!isNaN(parseFloat(v))) n.x = parseFloat(v); });
bindNode('nodeZ', (n, v) => { if (!isNaN(parseFloat(v))) n.z = parseFloat(v); });
$('mapName').addEventListener('input', () => { if (state.graph) { state.graph.name = $('mapName').value; state.dirty = true; updateSaveButton(); } });
$('deleteNode').onclick = deleteNode;
$('autoConnect').onclick = autoConnectIsolated;
$('deleteEdge').onclick = deleteEdge;

$('modeSelect').onclick = () => setMode('select');
$('modeAdd').onclick = () => setMode('add');
$('modeConnect').onclick = () => setMode('connect');
$('modePath').onclick = () => setMode('path');
$('fit').onclick = () => { fitView(); draw(); };
$('undo').onclick = undo;
$('redo').onclick = redo;
$('showPoints').onchange = draw; $('showLabels').onchange = draw;
$('save').onclick = saveVersion;
$('refresh').onclick = () => { state.current = null; loadSlugs().then(loadVersions).catch(e => setStatus(e.message, true)); };
$('slug').addEventListener('change', () => {
  let slug = $('slug').value;
  if (slug === NEW_MAP) {
    const name = prompt('Name for the new map (letters, digits, dashes). It appears on the server after the first save or upload.', 'greenhouse-2');
    slug = (name || '').toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-|-$/g, '');
    if (!slug) { $('slug').value = state.slug; return; }
    if (state.dirty && !confirm('Discard unsaved changes?')) { $('slug').value = state.slug; return; }
    state.slug = slug;
    state.current = null; state.points = null; state.pointsBitmap = null;
    state.graph = { name: name, pois: [], edges: [] }; state.dirty = false;
    loadSlugs().then(() => { renderVersions(); renderSidebar(); updateSaveButton(); fitView(); draw(); setStatus(`New map "${slug}". Add nodes or import JSON, then save; or upload a scan to it from the app.`); });
    return;
  }
  if (state.dirty && !confirm('Discard unsaved changes?')) { $('slug').value = state.slug; return; }
  state.slug = slug; state.current = null; state.graph = null; state.points = null; state.pointsBitmap = null; state.pendingPoints = null; state.dirty = false;
  state.clouds = new Map(); state.selectedCloud = null;
  loadVersions().catch(e => setStatus(e.message, true)); draw();
});

// ---------- Immersal import ----------
// Opens a finished Immersal scan as a new map. The route is then drawn straight
// in Immersal's coordinates and saved with an identity alignment to that map id,
// so the app and the glasses can use it without an alignment walk.
$('importImmersal').onclick = async () => {
  if (state.dirty && !confirm('Discard unsaved changes?')) return;
  const idText = prompt('Immersal map id (from the Mapper app or the Developer Portal):', '');
  if (idText === null || !idText.trim()) return;
  const btn = $('importImmersal'); btn.disabled = true;
  try {
    setStatus(`Fetching Immersal map ${idText.trim()}…`);
    // The site's own proxy adds the account token server side; nothing to type.
    const map = await ImmersalImport.fetchMap({ id: idText.trim(), base: '/immersal' });
    const name = (prompt(`Name for this map (it becomes the server key and what the app calls it):`, map.name) || '').trim();
    if (!name) { setStatus('Import cancelled.'); return; }
    map.name = name;
    const slug = ImmersalImport.slugFromName(map.name) || `immersal-${map.id}`;
    const taken = [...$('slug').options].some(o => o.value === slug);
    if (taken && !confirm(`A map called "${slug}" already exists on the server. Continue and save the import as its next version?`)) return;
    state.slug = slug; state.current = null; state.versions = []; state.history = []; state.future = [];
    state.graph = { name: map.name, pois: [], edges: [], immersalAlignment: ImmersalImport.identityAlignment(map.id) };
    state.clouds = new Map(); state.selectedCloud = null;
    state.points = map.points; state.pendingPoints = map.points; state.pointsBitmap = null;
    state.selectedNode = state.selectedEdge = null;
    computeHeights(); renderScanTools(); buildPointsBitmap();
    await loadSlugs();
    state.dirty = true; renderVersions(); renderSidebar(); updateSaveButton(); fitView(); draw();
    setStatus(`Imported "${map.name}" (Immersal ${map.id}): ${map.points.length / 3} points. Add places and paths, then save.`);
  } catch (e) {
    setStatus(`Import failed: ${e.message}`, true);
  } finally { btn.disabled = false; }
};

// ---------- Immersal maps: several scans lined up in one map ----------
// Each scan keeps its own coordinates; graph.immersalAlignment.maps holds where
// it sits in the map ({id, name, yaw, tx, ty, tz}), which the apps apply to a fix
// from that scan. The top-level yaw/tx/tz mirror the first scan for older builds.
// Lining up is by eye: on the Flower Dome scans an automatic snap latched onto
// wrong placements that scored as well as the right one.
const CLOUD_COLORS = ['#5aa9ff', '#ff9f43', '#2ecc71', '#e056fd', '#f7d794', '#ff6b6b', '#48dbfb', '#c8d6e5'];

function alignmentMaps() { const m = state.graph?.immersalAlignment?.maps; return Array.isArray(m) && m.length ? m : null; }
function placementOf(id) { return alignmentMaps()?.find(m => m.id === id) ?? null; }
function hasClouds() { return !!alignmentMaps() && state.clouds.size > 0; }

/// Gives a single-scan map its maps list, so a second scan can join it.
function ensureMaps() {
  const a = state.graph.immersalAlignment;
  if (!a) { state.graph.immersalAlignment = { mapIDs: [], yaw: 0, tx: 0, tz: 0, pairCount: 0, rmsError: 0, maps: [] }; return; }
  if (!Array.isArray(a.maps)) a.maps = (a.mapIDs || []).map(id => ({ id, name: `Immersal ${id}`, yaw: a.yaw || 0, tx: a.tx || 0, ty: 0, tz: a.tz || 0 }));
}

/// mapIDs and the top-level placement follow the maps list.
function syncAlignment() {
  const a = state.graph.immersalAlignment, maps = a.maps || [];
  a.mapIDs = maps.map(m => m.id);
  if (maps[0]) { a.yaw = maps[0].yaw; a.tx = maps[0].tx; a.tz = maps[0].tz; }
}

async function loadCloud(id) {
  const map = await ImmersalImport.fetchMap({ id, base: '/immersal' });
  const raw = map.points;
  const disp = CloudAlign.thin(raw, 25000), match = CloudAlign.thin(CloudAlign.voxelize(raw, 0.15), 6000);
  const used = new Set([...state.clouds.values()].map(c => c.color));
  const color = CLOUD_COLORS.find(c => !used.has(c)) || CLOUD_COLORS[state.clouds.size % CLOUD_COLORS.length];
  state.clouds.set(id, { id, raw, disp, match, centre: CloudAlign.centroid(disp), color, hidden: false });
}

const cloudFailed = new Set();   // scans whose cloud could not be fetched this session; not retried on every redraw
async function loadClouds() {
  const maps = alignmentMaps() || [];
  setStatus(`Loading ${maps.length} Immersal scan(s)…`);
  for (const m of maps) {
    if (state.clouds.has(m.id)) continue;
    if (cloudFailed.has(m.id)) continue;
    try { await loadCloud(m.id); } catch (e) { cloudFailed.add(m.id); setStatus(`Immersal ${m.id}: ${e.message}`, true); }
  }
  if (state.selectedCloud === null && maps[0]) state.selectedCloud = maps[0].id;
  renderClouds(); draw();
  setStatus(`${state.clouds.size} Immersal scan(s) loaded.`);
}

function drawClouds() {
  for (const cl of state.clouds.values()) {
    const pl = placementOf(cl.id); if (!pl || cl.hidden) continue;
    const selected = cl.id === state.selectedCloud && state.mode === 'cloud';
    ctx.fillStyle = cl.color; ctx.globalAlpha = state.mode === 'cloud' ? (selected ? 0.9 : 0.35) : 0.6;
    const c = Math.cos(pl.yaw), s = Math.sin(pl.yaw), k = state.view.scale;
    const size = selected ? 2 : 1.5;
    for (let i = 0; i < cl.disp.length; i += 3) {
      const x = cl.disp[i], z = cl.disp[i + 2];
      ctx.fillRect(state.view.ox + (c * x - s * z + pl.tx) * k, state.view.oy + (s * x + c * z + pl.tz) * k, size, size);
    }
  }
  ctx.globalAlpha = 1;
}

/// Where the scan's centre sits in the map, the point it turns about.
function cloudCentre(cl, pl) { const [x, , z] = CloudAlign.apply(pl, cl.centre[0], cl.centre[1], cl.centre[2]); return [x, z]; }

function turnAbout(pl, cl, dYaw) {
  const [cx, cz] = cloudCentre(cl, pl);
  const next = { ...pl, yaw: pl.yaw + dYaw, tx: 0, tz: 0 };
  const [qx, qz] = cloudCentre(cl, next);
  next.tx = cx - qx; next.tz = cz - qz;
  return next;
}

function setPlacement(id, next) {
  const pl = placementOf(id); if (!pl) return;
  let yaw = next.yaw; while (yaw > Math.PI) yaw -= 2 * Math.PI; while (yaw <= -Math.PI) yaw += 2 * Math.PI;
  Object.assign(pl, { yaw: +yaw.toFixed(5), tx: +next.tx.toFixed(3), ty: +(next.ty ?? pl.ty ?? 0).toFixed(3), tz: +next.tz.toFixed(3) });
  syncAlignment();
}

function dragCloud(wx, wz) {
  const d = state.drag, cl = state.clouds.get(state.selectedCloud); if (!cl) return;
  if (d.rotate) {
    const [cx, cz] = cloudCentre(cl, d.orig);
    const a0 = Math.atan2(d.wz - cz, d.wx - cx), a1 = Math.atan2(wz - cz, wx - cx);
    setPlacement(cl.id, turnAbout(d.orig, cl, a1 - a0));
  } else {
    setPlacement(cl.id, { ...d.orig, tx: d.orig.tx + wx - d.wx, tz: d.orig.tz + wz - d.wz });
  }
  d.moved = true; draw();
}

function nudgeCloud(dx, dz, dDeg) {
  const cl = state.clouds.get(state.selectedCloud), pl = placementOf(state.selectedCloud); if (!cl || !pl) return;
  beginChange();
  const moved = dDeg ? turnAbout(pl, cl, dDeg * Math.PI / 180) : { ...pl, tx: pl.tx + dx, tz: pl.tz + dz };
  setPlacement(cl.id, moved);
  state.dirty = true; updateSaveButton(); renderCloudEdit(); draw(); scheduleOverlap();
}

let overlapTimer = null;
function scheduleOverlap() { clearTimeout(overlapTimer); overlapTimer = setTimeout(showOverlap, 250); }

/// A rough guide only: how many of this scan's points have another scan's point
/// within 35 cm. Dense planting keeps it high even when slightly off, so the
/// eye on walkways and trunks is the real test.
function showOverlap() {
  const box = $('cloudOverlap'); const id = state.selectedCloud;
  const list = [...state.clouds.values()].map(cl => ({ match: cl.match, placement: placementOf(cl.id), hidden: cl.hidden }));
  const idx = [...state.clouds.keys()].indexOf(id);
  if (idx < 0 || list.length < 2) { box.textContent = ''; return; }
  const target = CloudAlign.targetFrom(list, idx);
  if (!target.length) { box.textContent = 'Show another scan to compare against.'; return; }
  const g = CloudAlign.buildGrid(target, 0.35);
  const f = CloudAlign.overlap(CloudAlign.thin(list[idx].match, 1200), g, list[idx].placement, 0.35);
  box.textContent = `Overlap with the other visible scans: ${(f * 100).toFixed(0)}% of points within 35 cm (a guide, not proof).`;
}

let cloudsLoading = false;
function renderClouds() {
  const panel = $('cloudsPanel'); panel.hidden = !state.graph;
  const maps = alignmentMaps() || [];
  // An undo can bring back a scan whose cloud was dropped: fetch it again.
  if (!cloudsLoading && maps.some(m => !state.clouds.has(m.id) && !cloudFailed.has(m.id)) && state.clouds.size) {
    cloudsLoading = true; loadClouds().finally(() => { cloudsLoading = false; });
  }
  $('cloudCount').textContent = maps.length ? `(${maps.length})` : '';
  const ul = $('cloudList'); ul.innerHTML = '';
  maps.forEach((m, i) => {
    const cl = state.clouds.get(m.id);
    const li = document.createElement('li'); if (m.id === state.selectedCloud) li.classList.add('active');
    li.innerHTML = `<i style="background:${cl?.color ?? '#555'}"></i><span>${escapeHTML(m.name || `Immersal ${m.id}`)} <span class="meta">${m.id}${i === 0 ? ' · first' : ''}${cl ? '' : ' · loading'}</span></span>`;
    const vis = document.createElement('input'); vis.type = 'checkbox'; vis.checked = !cl?.hidden; vis.title = 'Show this scan';
    vis.onclick = e => { e.stopPropagation(); if (cl) { cl.hidden = !vis.checked; draw(); scheduleOverlap(); } };
    li.appendChild(vis);
    li.onclick = () => { state.selectedCloud = m.id; renderClouds(); draw(); scheduleOverlap(); };
    ul.appendChild(li);
  });
  renderCloudEdit();
}

function renderCloudEdit() {
  const pl = placementOf(state.selectedCloud);
  $('cloudEdit').hidden = !pl; if (!pl) return;
  const deg = pl.yaw * 180 / Math.PI;
  $('cloudYawRange').value = deg.toFixed(1);
  if (document.activeElement !== $('cloudYaw')) $('cloudYaw').value = deg.toFixed(1);
  if (document.activeElement !== $('cloudTx')) $('cloudTx').value = pl.tx.toFixed(2);
  if (document.activeElement !== $('cloudTz')) $('cloudTz').value = pl.tz.toFixed(2);
  if (document.activeElement !== $('cloudTy')) $('cloudTy').value = (pl.ty ?? 0).toFixed(2);
}

$('addCloud').onclick = async () => {
  if (!state.graph) return;
  const idText = prompt('Immersal map id to add (from the Mapper app or the Developer Portal):', '');
  if (!idText) return;
  const id = parseInt(idText.trim(), 10);
  if (!Number.isInteger(id) || id <= 0) { setStatus('Map id must be a number.', true); return; }
  if (placementOf(id)) { setStatus(`Immersal ${id} is already in this map.`, true); return; }
  if ((alignmentMaps()?.length ?? 0) >= 8) { setStatus('Immersal localizes against at most 8 maps at once.', true); return; }
  const name = prompt('A name to show for it (e.g. "Points C 1 2 3"):', `Immersal ${id}`) || `Immersal ${id}`;
  $('addCloud').disabled = true;
  try {
    beginChange(); ensureMaps();
    // Scans already in the map need their clouds too, to line the new one up against.
    for (const m of alignmentMaps() || []) if (!state.clouds.has(m.id)) await loadCloud(m.id);
    setStatus(`Fetching Immersal ${id}…`);
    await loadCloud(id);
    const cl = state.clouds.get(id);
    // Start it in the middle of the view, heights roughly matched, for moving into place.
    const [wx, wz] = toWorld(canvas.clientWidth / 2, canvas.clientHeight / 2);
    const first = alignmentMaps()?.[0]; const firstCl = first && state.clouds.get(first.id);
    const ty = firstCl ? (firstCl.centre[1] + (first.ty || 0)) - cl.centre[1] : 0;
    state.graph.immersalAlignment.maps.push({ id, name, yaw: 0, tx: +(wx - cl.centre[0]).toFixed(3), ty: +ty.toFixed(3), tz: +(wz - cl.centre[2]).toFixed(3) });
    syncAlignment();
    state.selectedCloud = id; state.dirty = true; updateSaveButton(); renderClouds(); setMode('cloud'); draw(); scheduleOverlap();
    setStatus(`Added ${name}. Drag it into place (Alt/Option-drag turns it), then save.`);
  } catch (e) { setStatus(`Could not add Immersal ${id}: ${e.message}`, true); }
  finally { $('addCloud').disabled = false; }
};

$('moveCloud').onclick = () => setMode(state.mode === 'cloud' ? 'select' : 'cloud');
$('removeCloud').onclick = () => {
  const id = state.selectedCloud, maps = alignmentMaps(); if (!maps || !placementOf(id)) return;
  if (maps.length === 1) { setStatus('The last scan cannot be removed; the map needs one to position in.', true); return; }
  if (!confirm(`Remove Immersal ${id} from this map? Its scan stays on Immersal.`)) return;
  beginChange();
  state.graph.immersalAlignment.maps = maps.filter(m => m.id !== id); syncAlignment();
  state.clouds.delete(id); state.selectedCloud = alignmentMaps()?.[0]?.id ?? null;
  markDirty(); renderClouds();
};
const bindCloud = (el, apply) => $(el).addEventListener('input', () => {
  const pl = placementOf(state.selectedCloud); const v = parseFloat($(el).value); if (!pl || isNaN(v)) return;
  const cl = state.clouds.get(state.selectedCloud);
  setPlacement(pl.id, apply(pl, v, cl)); state.dirty = true; updateSaveButton(); renderCloudEdit(); draw(); scheduleOverlap();
});
['cloudYaw', 'cloudYawRange', 'cloudTx', 'cloudTz', 'cloudTy'].forEach(id => { $(id).addEventListener('focus', beginChange); $(id).addEventListener('pointerdown', beginChange); });
bindCloud('cloudYaw', (pl, v, cl) => turnAbout(pl, cl, v * Math.PI / 180 - pl.yaw));
bindCloud('cloudYawRange', (pl, v, cl) => turnAbout(pl, cl, v * Math.PI / 180 - pl.yaw));
bindCloud('cloudTx', (pl, v) => ({ ...pl, tx: v }));
bindCloud('cloudTz', (pl, v) => ({ ...pl, tz: v }));
bindCloud('cloudTy', (pl, v) => ({ ...pl, ty: v }));

// ---------- Scan view: height band, density, histogram ----------
// Lives in a collapsed disclosure in the sidebar; applies to the canvas and the 3D view.
const bandLo = $('bandLo'), bandHi = $('bandHi');
const sliderToY = v => { const h = state.heights; return h.min + (h.max - h.min) * v / 1000; };
const yToSlider = y => { const h = state.heights; return Math.round((y - h.min) / ((h.max - h.min) || 1) * 1000); };
function setBand(lo, hi, fromSlider) {
  if (!state.heights) return;
  const h = state.heights;
  if (lo === null) state.band = null; else state.band = { lo: Math.min(lo, hi), hi: Math.max(lo, hi) };
  const shownLo = state.band ? state.band.lo : h.min, shownHi = state.band ? state.band.hi : h.max;
  if (!fromSlider) { bandLo.value = yToSlider(shownLo); bandHi.value = yToSlider(shownHi); }
  $('bandLoV').textContent = `${shownLo.toFixed(2)} m`; $('bandHiV').textContent = `${shownHi.toFixed(2)} m`;
  state.pointsBitmap = null; buildPointsBitmap(); draw(); rebuild3D();
}
bandLo.addEventListener('input', () => setBand(sliderToY(+bandLo.value), sliderToY(+bandHi.value), true));
bandHi.addEventListener('input', () => setBand(sliderToY(+bandLo.value), sliderToY(+bandHi.value), true));
document.querySelectorAll('#scanTools [data-band]').forEach(b => b.onclick = () => {
  const h = state.heights; if (!h) return;
  if (b.dataset.band === 'all') setBand(null); else if (b.dataset.band === 'floor') setBand(h.med - 0.25, h.med + 0.15); else setBand(h.med + 0.3, h.med + 2.2);
});
$('density').addEventListener('change', () => { state.density = $('density').checked; state.pointsBitmap = null; buildPointsBitmap(); draw(); });

function renderScanTools() {
  const box = $('scanTools'); const h = state.heights;
  box.hidden = !h; if (!h) return;
  state.band = null; bandLo.value = 0; bandHi.value = 1000;
  $('bandLoV').textContent = `${h.min.toFixed(2)} m`; $('bandHiV').textContent = `${h.max.toFixed(2)} m`;
  // histogram of y in 0.25 m bins, largest bin labelled as the floor
  const pts = state.points, bin = 0.25, counts = new Map();
  const step = Math.max(1, Math.floor(pts.length / 3 / 60000));
  for (let i = 0; i < pts.length; i += 3 * step) { const k = Math.floor(pts[i + 1] / bin) * bin; counts.set(k, (counts.get(k) || 0) + 1); }
  const keys = [...counts.keys()].filter(k => counts.get(k) >= 4).sort((a, c) => a - c); const max = Math.max(1, ...keys.map(k => counts.get(k)));
  const W = 240, H = 110, left = 42, right = 6, top = 4, bottom = 14; const bh = Math.max(2, (H - top - bottom) / Math.max(1, keys.length) - 2); let s = '';
  keys.slice().reverse().forEach((k, i) => { const y = top + i * (bh + 2); const w = (W - left - right) * counts.get(k) / max;
    const t = Math.max(0, Math.min(1, (k + bin / 2 - h.lo) / ((h.hi - h.lo) || 1)));
    s += `<rect x="${left}" y="${y.toFixed(1)}" width="${Math.max(1, w).toFixed(1)}" height="${bh.toFixed(1)}" rx="1.5" fill="rgb(${Math.round(60 + 190 * t)},${Math.round(110 + 100 * t)},${Math.round(230 - 190 * t)})"/>`;
    if (i % 2 === 0 || keys.length < 8) s += `<text x="${left - 4}" y="${(y + bh * 0.8).toFixed(1)}" text-anchor="end">${k.toFixed(2)}</text>`;
    if (counts.get(k) === max) s += `<text x="${(left + w + 4).toFixed(1)}" y="${(y + bh * 0.8).toFixed(1)}">floor</text>`; });
  s += `<text x="${left}" y="${H - 2}">m, 0.25 m bins</text>`;
  $('heightHist').innerHTML = s;
}

// ---------- 3D overlay ----------
// three.js is fetched the first time the overlay opens, so the editor stays light.
const THREE_URL = 'https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js';
const v3 = { renderer: null, scene: null, cam: null, cloud: null, nodes: null, grid: null, centre: null, dist0: 10, orbit: { yaw: 0.6, pitch: 0.5, dist: 0 } };
function loadThree() {
  if (window.THREE) return Promise.resolve();
  return new Promise((res, rej) => { const s = document.createElement('script'); s.src = THREE_URL; s.onload = res; s.onerror = () => rej(new Error('could not load three.js')); document.head.appendChild(s); });
}
function open3D() {
  if (!state.points || !state.points.length) { setStatus('No point cloud loaded for this version.', true); return; }
  $('view3d').hidden = false; $('status3d').textContent = 'Loading…';
  loadThree().then(() => { init3D(); rebuild3D(true); $('status3d').textContent = `${state.points.length / 3} points · nodes shown as dots at floor height`; })
    .catch(e => { $('status3d').textContent = e.message; });
}
function close3D() { $('view3d').hidden = true; }
$('open3d').onclick = open3D; $('close3d').onclick = close3D;
document.addEventListener('keydown', e => { if (e.key === 'Escape' && !$('view3d').hidden) close3D(); });
function init3D() {
  if (v3.renderer) return;
  const cv3 = $('canvas3d');
  v3.renderer = new THREE.WebGLRenderer({ canvas: cv3, antialias: true }); v3.renderer.setClearColor(0x0c0e14);
  v3.scene = new THREE.Scene(); v3.cam = new THREE.PerspectiveCamera(50, 1, 0.05, 1000);
  let drag = null; const touches = new Map(); let pinch = null;
  cv3.addEventListener('pointerdown', e => { cv3.setPointerCapture(e.pointerId); touches.set(e.pointerId, e); cv3.classList.add('drag');
    if (touches.size === 2) { const [a, b] = [...touches.values()]; pinch = { d: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY), dist: v3.orbit.dist }; drag = null; }
    else drag = { x: e.clientX, y: e.clientY, yaw: v3.orbit.yaw, pitch: v3.orbit.pitch }; });
  cv3.addEventListener('pointermove', e => { if (touches.has(e.pointerId)) touches.set(e.pointerId, e);
    if (pinch && touches.size === 2) { const [a, b] = [...touches.values()]; v3.orbit.dist = Math.max(0.5, Math.min(v3.dist0 * 5, pinch.dist * pinch.d / Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY))); render3D(); return; }
    if (!drag) return; v3.orbit.yaw = drag.yaw - (e.clientX - drag.x) * 0.008; v3.orbit.pitch = Math.max(-1.4, Math.min(1.5, drag.pitch + (e.clientY - drag.y) * 0.006)); render3D(); });
  const end = e => { touches.delete(e.pointerId); if (touches.size < 2) pinch = null; if (!touches.size) { drag = null; cv3.classList.remove('drag'); } };
  cv3.addEventListener('pointerup', end); cv3.addEventListener('pointercancel', end);
  cv3.addEventListener('wheel', e => { e.preventDefault(); v3.orbit.dist = Math.max(0.5, Math.min(v3.dist0 * 5, v3.orbit.dist * Math.exp(e.deltaY * 0.0015))); render3D(); }, { passive: false });
  const reset = () => { v3.orbit.yaw = 0.6; v3.orbit.pitch = 0.5; v3.orbit.dist = v3.dist0; render3D(); };
  cv3.addEventListener('dblclick', reset); $('reset3d').onclick = reset;
  window.addEventListener('resize', () => { if (!$('view3d').hidden) render3D(); });
}
function rebuild3D(recentre = false) {
  if (!v3.renderer || $('view3d').hidden || !state.points) return;
  const pts = state.points, h = state.heights || { lo: -1, hi: 1, med: 0 };
  const b = contentBounds(true);
  if (recentre || !v3.centre) {
    v3.centre = new THREE.Vector3((b.minX + b.maxX) / 2, h.med, (b.minZ + b.maxZ) / 2);
    const span = Math.max(b.maxX - b.minX, b.maxZ - b.minZ, 2); v3.dist0 = span * 1.15; v3.orbit.dist = v3.dist0;
    if (v3.grid) v3.scene.remove(v3.grid);
    v3.grid = new THREE.GridHelper(Math.ceil(span) + 4, Math.ceil(span) + 4, 0x3a4150, 0x22262f); v3.grid.position.set(v3.centre.x, h.med - 0.02, v3.centre.z); v3.scene.add(v3.grid);
  }
  const step = Math.max(1, Math.floor(pts.length / 3 / 400000)); const idx = [];
  for (let i = 0; i < pts.length / 3; i += step) { const x = pts[i * 3], y = pts[i * 3 + 1], z = pts[i * 3 + 2];
    if (inBand(y) && x >= b.minX - 1 && x <= b.maxX + 1 && z >= b.minZ - 1 && z <= b.maxZ + 1) idx.push(i); }
  const pos = new Float32Array(idx.length * 3), col = new Float32Array(idx.length * 3);
  idx.forEach((i, k) => { const y = pts[i * 3 + 1]; const t = Math.max(0, Math.min(1, (y - h.lo) / ((h.hi - h.lo) || 1)));
    pos[k * 3] = pts[i * 3]; pos[k * 3 + 1] = y; pos[k * 3 + 2] = pts[i * 3 + 2];
    col[k * 3] = (60 + 190 * t) / 255; col[k * 3 + 1] = (110 + 100 * t) / 255; col[k * 3 + 2] = (230 - 190 * t) / 255; });
  if (v3.cloud) { v3.scene.remove(v3.cloud); v3.cloud.geometry.dispose(); }
  const geo = new THREE.BufferGeometry(); geo.setAttribute('position', new THREE.BufferAttribute(pos, 3)); geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  v3.cloud = new THREE.Points(geo, new THREE.PointsMaterial({ size: 0.08, vertexColors: true })); v3.scene.add(v3.cloud);
  // the route graph, as dots on the floor plane so markers can be judged against the room
  if (v3.nodes) { v3.scene.remove(v3.nodes); }
  v3.nodes = new THREE.Group();
  (state.graph?.pois || []).forEach(p => { const m = new THREE.Mesh(new THREE.SphereGeometry(0.12, 12, 12), new THREE.MeshBasicMaterial({ color: CATEGORY_COLORS[p.category] || '#9aa0a6' })); m.position.set(p.x, h.med + 0.12, p.z); v3.nodes.add(m); });
  v3.scene.add(v3.nodes);
  render3D();
}
function render3D() {
  if (!v3.renderer || $('view3d').hidden) return;
  const cv3 = $('canvas3d'); const r = cv3.getBoundingClientRect();
  v3.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1)); v3.renderer.setSize(r.width, r.height, false); v3.cam.aspect = r.width / r.height; v3.cam.updateProjectionMatrix();
  const o = v3.orbit, d = o.dist || v3.dist0, cp = Math.cos(o.pitch), c = v3.centre;
  v3.cam.position.set(c.x + d * cp * Math.sin(o.yaw), c.y + d * Math.sin(o.pitch), c.z + d * cp * Math.cos(o.yaw)); v3.cam.lookAt(c);
  v3.renderer.render(v3.scene, v3.cam);
}

$('exportJSON').onclick = () => {
  if (!state.graph) return;
  const blob = new Blob([JSON.stringify(state.graph, null, 2)], { type: 'application/json' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `${state.slug}-v${state.current?.version ?? 'draft'}.map.json`; a.click();
};
$('importJSON').addEventListener('change', async ev => {
  const file = ev.target.files[0]; if (!file) return;
  try {
    const g = JSON.parse(await file.text());
    if (!Array.isArray(g.pois) || !Array.isArray(g.edges)) throw new Error('expected {name, pois, edges}');
    if (state.graph) beginChange(); else { state.history = []; state.future = []; }
    state.graph = g; state.selectedNode = state.selectedEdge = null; markDirty(); fitView(); draw();
    setStatus(`Imported ${g.pois.length} nodes from ${file.name}. Save to publish.`);
  } catch (e) { setStatus(`Import failed: ${e.message}`, true); }
  ev.target.value = '';
});

window.addEventListener('beforeunload', ev => { if (state.dirty) { ev.preventDefault(); ev.returnValue = ''; } });
window.addEventListener('resize', resize);

// ---------- boot ----------
resize();
loadSlugs().then(loadVersions).catch(e => setStatus(`Could not load versions: ${e.message}`, true));
