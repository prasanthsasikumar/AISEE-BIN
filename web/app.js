// AISEE-BIN map editor. Vanilla JS, talks to the shared Supabase REST + Storage API.
'use strict';

// Supabase Cloud, project djfpemdkeguztyuerxqc (ap-southeast-1). Moved off the
// self-hosted VPS on 2026-09-09; storage here is CDN-fronted, so the point cloud
// loads in seconds rather than minutes.
const SUPABASE_URL = 'https://djfpemdkeguztyuerxqc.supabase.co';
const SUPABASE_KEY = 'sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL';
const BUCKET = 'aiseebin-maps';
// Same dots as the phone apps' place types.
const CATEGORY_COLORS = { destination: '#5B7CFA', junction: '#8E8AA3', exhibit: '#1FA97A', hazard: '#E0524A' };
const colorOf = p => CATEGORY_COLORS[p.category] || CATEGORY_COLORS.destination;

// ---------- state ----------
const state = {
  slug: null,
  maps: [],               // newest version of every map, for Maps and the map chip
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
  draftSavedAt: null,     // when the unpublished edits were last kept in this browser
  waypointsOpen: false,   // the Waypoints group in Places is expanded
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
  $('undo').disabled = $('mmUndo').disabled = !state.history.length;
  $('redo').disabled = $('mmRedo').disabled = !state.future.length;
}

/// Undo steps that changed something (focusing a field records one that may not).
function changeCount() {
  let n = 0;
  for (let i = 0; i < state.history.length; i++) if (state.history[i] !== (state.history[i + 1] ?? snapshot())) n++;
  return n;
}

const $ = id => document.getElementById(id);
const canvas = $('canvas');
const ctx = canvas.getContext('2d');

// ---------- formatting and icons ----------
const fmtInt = n => Math.round(n).toLocaleString('en-US').replace(/,/g, '\u202f');
const fmtCoord = v => v.toFixed(2).replace('-', '−');
const shortDate = iso => new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
const timeOnly = iso => new Date(iso).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
const dateTime = iso => `${shortDate(iso)}, ${timeOnly(iso)}`;
const svgIcon = body => `<svg class="ic" viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
const ICON = {
  check: svgIcon('<path d="M20 6 9 17l-5-5"/>'),
  warn: svgIcon('<path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17v.01"/>'),
  x: svgIcon('<path d="M6 6l12 12M18 6 6 18"/>'),
  chevron: svgIcon('<path d="M9 6l6 6-6 6"/>'),
};
const ICON_PHONE = svgIcon('<rect x="6" y="2" width="12" height="20" rx="2"/>');

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

// ---------- maps (home) ----------
/// One card per map: its newest version, plus that version's places and
/// connections for the thumbnail (fetched for those rows only).
async function loadMaps() {
  const rows = await rest('ab_map_versions?select=id,map_slug,version,source,created_at,node_count,name:graph->>name&order=map_slug.asc,version.desc');
  const latest = new Map();
  for (const r of rows) if (!latest.has(r.map_slug)) latest.set(r.map_slug, r);
  const maps = [...latest.values()];
  if (maps.length) {
    const shapes = await rest(`ab_map_versions?id=in.(${maps.map(m => m.id).join(',')})&select=id,pois:graph->pois,edges:graph->edges`).catch(() => []);
    const byId = new Map(shapes.map(s => [s.id, s]));
    for (const m of maps) { const s = byId.get(m.id); m.pois = Array.isArray(s?.pois) ? s.pois : []; m.edges = Array.isArray(s?.edges) ? s.edges : []; }
  }
  maps.sort((a, b) => b.created_at.localeCompare(a.created_at));
  state.maps = maps;
  renderHome(); renderMapMenu();
  if (document.body.dataset.view === 'home') setStatus(`Connected to server · ${maps.length} map${maps.length === 1 ? '' : 's'}`);
}

const mapName = m => m.name || m.map_slug;
const newMapCard = $('newMapCard');

function renderHome() {
  const q = $('mapSearch').value.trim().toLowerCase();
  const shown = state.maps.filter(m => !q || mapName(m).toLowerCase().includes(q) || m.map_slug.includes(q));
  $('mapCount').textContent = `Your maps (${state.maps.length})`;
  $('mapGrid').replaceChildren(...shown.map(mapCard), newMapCard);
}

function mapCard(m) {
  const card = document.createElement('article');
  const current = m.map_slug === state.slug && !!state.graph;
  card.className = 'mapCard' + (current ? ' current' : '');
  const draft = readDraft(m.map_slug);
  const places = m.pois.filter(p => p.category !== 'junction').length;
  card.innerHTML = `<div class="thumb">${thumbSVG(m)}${draft
      ? '<span class="badge draft">Unpublished edits</span>'
      : `<span class="badge live">${ICON.check}Published</span>`}</div>
    <div class="cardBody"><div><h3></h3><p></p></div><button class="btn">Edit map</button></div>`;
  card.querySelector('h3').textContent = mapName(m);
  card.querySelector('p').textContent = `v${m.version} · ${places} place${places === 1 ? '' : 's'} · edited ${shortDate(m.created_at)}`;
  card.querySelector('button').setAttribute('aria-label', `Edit ${mapName(m)}`);
  card.onclick = () => openMap(m.map_slug);
  return card;
}

/// The route graph drawn small: connections as lines, places as dots in their type colour.
function thumbSVG(m) {
  const pois = m.pois.filter(p => Number.isFinite(p.x) && Number.isFinite(p.z));
  if (!pois.length) return '<span class="thumbEmpty">No places yet</span>';
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  for (const p of pois) { minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x); minZ = Math.min(minZ, p.z); maxZ = Math.max(maxZ, p.z); }
  const W = 300, H = 170, pad = 24;
  const s = Math.min((W - 2 * pad) / Math.max(1, maxX - minX), (H - 2 * pad) / Math.max(1, maxZ - minZ));
  const cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
  const X = x => (W / 2 + (x - cx) * s).toFixed(1), Y = z => (H / 2 + (z - cz) * s).toFixed(1);
  const byId = new Map(pois.map(p => [p.id, p]));
  const lines = m.edges.map(e => { const a = byId.get(e.from), b = byId.get(e.to); return a && b ? `<line x1="${X(a.x)}" y1="${Y(a.z)}" x2="${X(b.x)}" y2="${Y(b.z)}"/>` : ''; }).join('');
  const dots = pois.map(p => `<circle cx="${X(p.x)}" cy="${Y(p.z)}" r="${p.category === 'junction' ? 2.5 : 4.5}" fill="${colorOf(p)}"/>`).join('');
  return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" aria-hidden="true"><g stroke="#C8C2DC" stroke-opacity=".45" stroke-width="1.5" stroke-linecap="round">${lines}</g><g stroke="#0F0D16" stroke-width="1.5">${dots}</g></svg>`;
}

function renderMapMenu() {
  const box = $('mapMenuList'); box.replaceChildren();
  const maps = [...state.maps].sort((a, b) => mapName(a).localeCompare(mapName(b)));
  if (!maps.some(m => m.map_slug === state.slug) && state.graph) maps.unshift({ map_slug: state.slug, name: state.graph.name, version: null });
  for (const m of maps) {
    const b = document.createElement('button'); b.setAttribute('role', 'menuitem');
    const current = m.map_slug === state.slug;
    if (current) b.className = 'current';
    b.innerHTML = `${current ? ICON.check : ''}<span class="grow"></span><span class="mono">${m.version ? `v${m.version}` : 'new'}</span>`;
    b.insertBefore(document.createTextNode(m.map_slug === state.slug && state.graph?.name ? state.graph.name : mapName(m)), b.querySelector('.grow'));
    b.onclick = () => { closeMenus(); openMap(m.map_slug); };
    box.appendChild(b);
  }
}

// ---------- routing: #/ is Maps, #/map/<slug> the editor ----------
function openMap(slug) { const h = `#/map/${encodeURIComponent(slug)}`; if (location.hash === h) route(); else location.hash = h; }

function route() {
  const m = location.hash.match(/^#\/map\/(.+)$/);
  if (m) enterMap(decodeURIComponent(m[1])); else showView('home');
}

function showView(view) {
  saveDraftNow(); closeMenus(); closeSheets();
  document.body.dataset.view = view;
  $('home').hidden = view !== 'home'; $('editor').hidden = view !== 'editor';
  if (view === 'home') {
    renderHome(); renderFooterRight();
    loadMaps().catch(e => setStatus(`Could not load maps: ${e.message}`, true));
  } else {
    resize(); renderFooterRight();
  }
}

async function enterMap(slug) {
  if (slug === state.slug && state.graph) { showView('editor'); return; }
  if (!leaveMapOk()) { history.replaceState(null, '', state.graph ? `#/map/${encodeURIComponent(state.slug)}` : '#/'); route(); return; }
  resetMapState(slug);
  showView('editor'); renderSidebar(); draw();
  try { await loadVersions(); } catch (e) { setStatus(`Could not load ${slug}: ${e.message}`, true); }
}

function resetMapState(slug) {
  Object.assign(state, {
    slug, current: null, versions: [], graph: null, points: null, pendingPoints: null, pointsBitmap: null, heights: null, band: null,
    dirty: false, history: [], future: [], clouds: new Map(), selectedCloud: null, draftSavedAt: null,
    selectedNode: null, selectedEdge: null, connectFrom: null, pathFrom: null,
  });
  updateUndoButtons(); renderScanTools(); setMode('select');
}

/// Unpublished edits live on as a draft, so leaving a map only loses an
/// Immersal import, whose point cloud is too big to keep in the browser.
function leaveMapOk() {
  if (!state.dirty) return true;
  if (state.pendingPoints) return confirm('This Immersal import has not been published, and it cannot be kept as a draft. Leave it?');
  saveDraftNow();
  return true;
}

// ---------- drafts ----------
// Edits are kept in this browser per map, the same as Walk & mark on the phone:
// closing the tab or switching maps loses nothing, and visitors see none of it
// until Publish.
const DRAFT_PREFIX = 'aiseebin-draft:';
function readDraft(slug) { try { return JSON.parse(localStorage.getItem(DRAFT_PREFIX + slug)); } catch { return null; } }
function clearDraft(slug = state.slug) { clearTimeout(draftTimer); try { localStorage.removeItem(DRAFT_PREFIX + slug); } catch {} state.draftSavedAt = null; renderFooterRight(); }
let draftTimer = null;
function scheduleDraft() { clearTimeout(draftTimer); draftTimer = setTimeout(saveDraftNow, 600); }
function saveDraftNow() {
  clearTimeout(draftTimer);
  if (!state.dirty || !state.graph || state.pendingPoints) return;
  const savedAt = new Date().toISOString();
  try {
    localStorage.setItem(DRAFT_PREFIX + state.slug, JSON.stringify({ baseId: state.current?.id ?? null, baseVersion: state.current?.version ?? null, savedAt, graph: state.graph }));
    state.draftSavedAt = savedAt;
  } catch { state.draftSavedAt = null; }
  renderFooterRight();
}

function offerDraft(baseId, label) {
  const draft = readDraft(state.slug);
  if (!draft || (draft.baseId ?? null) !== baseId || !draft.graph) return false;
  if (!confirm(`You have unpublished edits to ${label} from ${dateTime(draft.savedAt)}. Restore them?`)) { clearDraft(); return false; }
  state.graph = draft.graph; state.graph.pois ??= []; state.graph.edges ??= [];
  state.dirty = true; state.draftSavedAt = draft.savedAt;
  return true;
}

// ---------- versions ----------
async function fetchVersions() {
  // `node_count` is a computed column (see server/schema.sql): it gives History
  // its "N places" without dragging every version's whole graph across the wire.
  state.versions = await rest(`ab_map_versions?map_slug=eq.${encodeURIComponent(state.slug)}&select=id,version,source,note,point_count,created_at,worldmap_path,pointcloud_path,node_count&order=version.desc`);
  renderVersions(); renderHeader();
}

async function loadVersions() {
  setStatus('Loading versions…', false, true);
  state.loading = true;
  try { await fetchVersions(); } finally { state.loading = false; }
  if (!state.versions.length) {
    if (!state.graph && !offerDraft(null, 'this new map')) state.graph = { name: state.slug, pois: [], edges: [] };
    renderSidebar(); updateSaveButton(); fitView(); draw();
    setStatus('Not published yet. Publish a scan from the phone (New map → step 3), or add places here and publish.');
    return;
  }
  setStatus(`${state.versions.length} version(s).`);
  if (!state.current) {
    // A draft reopens on the version it was made from, so the restore offer applies.
    const draft = readDraft(state.slug);
    await loadVersion(state.versions.find(v => v.id === draft?.baseId) || state.versions[0]);
  }
}

async function loadVersion(row) {
  if (state.dirty) { if (!confirm('Discard your unpublished edits?')) return; clearDraft(); state.dirty = false; }
  // The version list is fetched without `graph`, so pull it for the one being opened.
  if (!row.graph) {
    setStatus(`Loading v${row.version}…`, false, true);
    const [full] = await rest(`ab_map_versions?id=eq.${encodeURIComponent(row.id)}&select=graph`);
    if (!full) { setStatus(`Version ${row.version} has gone missing.`, true); return; }
    row.graph = full.graph;
  }
  state.current = row;
  state.graph = JSON.parse(JSON.stringify(row.graph));
  state.graph.pois ??= []; state.graph.edges ??= [];
  state.selectedNode = state.selectedEdge = state.connectFrom = state.pathFrom = null;
  state.dirty = false; state.draftSavedAt = null;
  offerDraft(row.id, `v${row.version}`);
  state.history = []; state.future = []; updateUndoButtons();
  state.points = null; state.pointsBitmap = null; state.heights = null; renderScanTools();
  renderVersions(); renderSidebar(); updateSaveButton(); renderFiles();
  fitView(); draw();
  state.clouds = new Map(); state.selectedCloud = null; renderClouds();
  if (alignmentMaps()) loadClouds().then(() => { fitView(); draw(); });
  const placesText = () => `${state.graph.pois.length} places, ${state.graph.edges.length} connections`;
  if (row.pointcloud_path) {
    setStatus(`Loading ${row.point_count ? fmtInt(row.point_count) : ''} points…`, false, true);
    try {
      const buf = await fetchMaybeGzipped(publicURL(row.pointcloud_path));
      if (state.current !== row) return;   // another version or map was opened meanwhile
      state.points = new Float32Array(buf);
      computeHeights(); renderScanTools(); buildPointsBitmap();
      setStatus(`Loaded v${row.version} — ${placesText()}, ${fmtInt(state.points.length / 3)} points`);
    } catch (e) { setStatus(`Point cloud failed: ${e.message}`, true); }
    fitView(); draw();
  } else {
    setStatus(`Loaded v${row.version} — ${placesText()}`);
  }
}

async function publishVersion() {
  if (!state.graph) return;
  const btn = $('publishConfirm'); btn.disabled = true; $('publishConfirmLabel').textContent = 'Publishing…';
  $('publishError').hidden = true;
  try {
    setStatus('Publishing…', false, true);
    const version = await rest('rpc/ab_next_version', { method: 'POST', body: JSON.stringify({ slug: state.slug }) });
    let pointcloudPath = state.current?.pointcloud_path ?? null, pointCount = state.current?.point_count ?? null;
    if (state.pendingPoints) {
      // Same layout the app uses, minus gzip: the cloud is small and the browser
      // has no cheap way to compress a Float32Array.
      pointcloudPath = `${state.slug}/v${version}/points.f32`;
      pointCount = state.pendingPoints.length / 3;
      setStatus(`Uploading ${fmtInt(pointCount)} points…`, false, true);
      await uploadObject(pointcloudPath, state.pendingPoints);
    }
    const row = {
      map_slug: state.slug, version, source: 'web', note: $('note').value.trim() || null,
      graph: state.graph,
      worldmap_path: state.current?.worldmap_path ?? null,
      pointcloud_path: pointcloudPath,
      point_count: pointCount,
    };
    const [saved] = await rest('ab_map_versions', { method: 'POST', body: JSON.stringify(row), headers: { Prefer: 'return=representation' } });
    state.pendingPoints = null;
    state.dirty = false; $('note').value = '';
    clearDraft();
    state.current = saved;
    state.history = []; state.future = []; updateUndoButtons();
    $('publishDialog').close();
    await fetchVersions();
    renderSidebar(); updateSaveButton();
    loadMaps().catch(() => {});   // a renamed map relabels its card and menu entry
    setStatus(`Published v${saved.version}. Visitors get it the next time they open the map.`);
  } catch (e) {
    $('publishError').textContent = `Publish failed: ${e.message}`; $('publishError').hidden = false;
    setStatus(`Publish failed: ${e.message}`, true);
  } finally {
    btn.disabled = false; renderPublishLabel();
  }
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

function hitNode(sx, sy, tol = 12) {
  if (!state.graph) return null;
  for (let i = state.graph.pois.length - 1; i >= 0; i--) {
    const p = state.graph.pois[i]; const [x, y] = toScreen(p.x, p.z);
    if (dist(sx, sy, x, y) <= tol) return p;
  }
  return null;
}

function hitEdge(sx, sy, tol = 6) {
  if (!state.graph) return null;
  for (let i = 0; i < state.graph.edges.length; i++) {
    const e = state.graph.edges[i]; const a = nodeById(e.from), b = nodeById(e.to);
    if (!a || !b) continue;
    const [ax, ay] = toScreen(a.x, a.z), [bx, by] = toScreen(b.x, b.z);
    if (pointToSegment(sx, sy, ax, ay, bx, by) <= tol) return i;
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
  const w = canvas.clientWidth, h = canvas.clientHeight;
  // The editor may still be hidden (opening a map); fit once it has a size.
  if (!w || !h) { state.fitPending = true; return; }
  state.fitPending = false;
  const b = contentBounds(true);
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
const SANS = "'IBM Plex Sans', system-ui, sans-serif", MONO = "'IBM Plex Mono', ui-monospace, monospace";

function resize() {
  const dpr = window.devicePixelRatio || 1;
  canvas.width = canvas.clientWidth * dpr; canvas.height = canvas.clientHeight * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  if (state.fitPending) fitView();
  draw();
}

function draw() {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  if (!w || !h) return;
  ctx.clearRect(0, 0, w, h);
  drawGrid(w, h);
  if ($('showPoints').checked) drawPoints();
  if (!state.graph) return;
  const showLabels = $('showLabels').checked, showDistances = $('showDistances').checked;
  const sel = state.selectedNode;

  // connections
  ctx.lineCap = 'round';
  state.graph.edges.forEach((e, i) => {
    const a = nodeById(e.from), b = nodeById(e.to); if (!a || !b) return;
    const [ax, ay] = toScreen(a.x, a.z), [bx, by] = toScreen(b.x, b.z);
    const selected = i === state.selectedEdge;
    ctx.strokeStyle = selected ? '#B9A6FF' : 'rgba(200,194,220,.85)';
    ctx.lineWidth = selected ? 4 : 2.5;
    ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by); ctx.stroke();
    if (showDistances) {
      ctx.fillStyle = selected ? '#B9A6FF' : '#8B85A6'; ctx.font = `11px ${MONO}`;
      ctx.fillText(`${Math.hypot(a.x - b.x, a.z - b.z).toFixed(1)} m`, (ax + bx) / 2 + 6, (ay + by) / 2 - 6);
    }
  });

  // origin and forward (−z)
  const [ox, oy] = toScreen(0, 0);
  ctx.strokeStyle = 'rgba(247,245,253,.55)'; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(ox - 7, oy); ctx.lineTo(ox + 7, oy); ctx.moveTo(ox, oy + 7); ctx.lineTo(ox, oy - 7); ctx.stroke();
  ctx.strokeStyle = '#5EE6A8'; ctx.lineWidth = 2.5;
  ctx.beginPath(); ctx.moveTo(ox, oy - 7); ctx.lineTo(ox, oy - 29); ctx.stroke();
  ctx.fillStyle = '#5EE6A8'; ctx.font = `11px ${MONO}`; ctx.fillText('forward', ox + 9, oy - 22);

  // places
  const isolatedIds = new Set(isolatedPlaces().map(p => p.id));
  const draw1 = p => {
    const [x, y] = toScreen(p.x, p.z);
    const junction = p.category === 'junction', r = junction ? 7 : 9, color = colorOf(p);
    const radius = announceRadius(p);
    if (radius > 0) {
      ctx.beginPath(); ctx.arc(x, y, radius * state.view.scale, 0, Math.PI * 2);
      ctx.strokeStyle = color + (p === sel ? 'cc' : '60'); ctx.lineWidth = p === sel ? 1.6 : 1;
      ctx.setLineDash([5, 6]); ctx.stroke(); ctx.setLineDash([]);
    }
    if (isolatedIds.has(p.id)) {
      ctx.beginPath(); ctx.arc(x, y, r + 7, 0, Math.PI * 2);
      ctx.strokeStyle = '#FFC24B'; ctx.lineWidth = 2; ctx.setLineDash([3, 3]); ctx.stroke(); ctx.setLineDash([]);
    }
    if (p === sel) { ctx.beginPath(); ctx.arc(x, y, r + 9, 0, Math.PI * 2); ctx.strokeStyle = '#B9A6FF'; ctx.lineWidth = 3; ctx.stroke(); }
    if (p === state.connectFrom || p === state.pathFrom) { ctx.beginPath(); ctx.arc(x, y, r + 5, 0, Math.PI * 2); ctx.strokeStyle = '#FFC24B'; ctx.lineWidth = 3; ctx.stroke(); }
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = color; ctx.fill(); ctx.strokeStyle = '#0F0D16'; ctx.lineWidth = 2; ctx.stroke();
    if (showLabels) {
      ctx.font = p === sel ? `600 15px ${SANS}` : `13px ${SANS}`;
      ctx.fillStyle = p === sel ? '#F7F5FD' : junction ? '#C8C2DC' : '#DCD7EA';
      ctx.fillText(p.name, x + r + (p === sel ? 9 : 6), y + 4.5);
    }
  };
  state.graph.pois.forEach(p => { if (p !== sel) draw1(p); });
  if (sel) draw1(sel);   // on top of its neighbours
}

function drawGrid(w, h) {
  const s = state.view.scale; const step = s < 12 ? 5 : 1;
  const [x0, z0] = toWorld(0, 0), [x1, z1] = toWorld(w, h);
  // Labels at least ~56 px apart, so zoomed out they thin instead of overlapping.
  const every = [5, 10, 20, 50, 100, 200].find(k => k * s >= 56) || 500;
  ctx.lineWidth = 1; ctx.font = `11px ${MONO}`; ctx.fillStyle = '#6E6889';
  for (let x = Math.floor(x0 / step) * step; x <= x1; x += step) {
    const [sx] = toScreen(x, 0); ctx.strokeStyle = x % 5 === 0 ? 'rgba(247,245,253,.11)' : 'rgba(247,245,253,.045)';
    ctx.beginPath(); ctx.moveTo(sx, 0); ctx.lineTo(sx, h); ctx.stroke();
    if (x % every === 0 && sx > 48) ctx.fillText(`x ${x}`.replace('-', '−'), sx + 4, 14);
  }
  for (let z = Math.floor(z0 / step) * step; z <= z1; z += step) {
    const [, sy] = toScreen(0, z); ctx.strokeStyle = z % 5 === 0 ? 'rgba(247,245,253,.11)' : 'rgba(247,245,253,.045)';
    ctx.beginPath(); ctx.moveTo(0, sy); ctx.lineTo(w, sy); ctx.stroke();
    if (z % every === 0 && sy > 32) ctx.fillText(`z ${z}`.replace('-', '−'), 6, sy - 4);
  }
}

function drawPoints() {
  if (hasClouds()) { drawClouds(); return; }
  if (state.pointsBitmap) {
    const m = state.pointsBitmapMeta; const [sx, sy] = toScreen(m.minX, m.minZ);
    const k = state.view.scale / m.scale;
    ctx.imageSmoothingEnabled = k < 1;
    ctx.globalAlpha = 0.9;
    ctx.drawImage(state.pointsBitmap, sx, sy, state.pointsBitmap.width * k, state.pointsBitmap.height * k);
    ctx.globalAlpha = 1;
  } else if (state.points) {
    ctx.fillStyle = 'rgba(120,168,255,.5)';
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

function unreachableText(isolated) {
  return isolated.length === 1
    ? `“${isolated[0].name}” isn’t connected to the route`
    : `${isolated.length} places aren’t connected to the route: ${isolated.map(p => p.name).join(', ')}`;
}

function renderConnectivity() {
  const isolated = isolatedPlaces();
  const box = $('connectivity');
  box.hidden = !state.graph?.pois.some(p => p.category !== 'junction');
  box.className = 'reach ' + (isolated.length ? 'warn' : 'ok');
  $('reachIcon').innerHTML = isolated.length ? ICON.warn : ICON.check;
  $('reachText').textContent = isolated.length ? unreachableText(isolated) : 'Every place can be reached';
  $('autoConnect').hidden = !isolated.length;
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
  setStatus(`Connected ${isolated.length} place(s) to the nearest place. Check the new connections, then publish.`);
}

// ---------- left rail: Places and History ----------
function setTab(tab) {
  const places = tab === 'places';
  $('tabPlaces').classList.toggle('active', places); $('tabPlaces').setAttribute('aria-selected', places);
  $('tabHistory').classList.toggle('active', !places); $('tabHistory').setAttribute('aria-selected', !places);
  $('placesPane').hidden = !places; $('historyPane').hidden = places;
}

function renderPlaces() {
  const g = state.graph, ul = $('placeList');
  ul.replaceChildren();
  $('placeCount').textContent = g ? g.pois.length : '';
  if (!g) return;
  if (!g.pois.length) { ul.innerHTML = '<li class="empty">No places yet. Choose <b>Place</b>, then click the map — or walk the site with the phone and publish from there.</li>'; return; }
  const q = $('placeSearch').value.trim().toLowerCase();
  const match = p => !q || p.name.toLowerCase().includes(q) || (p.aliases || []).some(a => a.toLowerCase().includes(q));
  const degree = new Map();
  g.edges.forEach(e => { degree.set(e.from, (degree.get(e.from) || 0) + 1); degree.set(e.to, (degree.get(e.to) || 0) + 1); });
  const named = g.pois.filter(p => p.category !== 'junction' && match(p)).sort((a, b) => a.name.localeCompare(b.name));
  const junctions = g.pois.filter(p => p.category === 'junction' && match(p));
  named.forEach(p => ul.appendChild(placeRow(p, degree)));
  if (junctions.length) {
    const open = state.waypointsOpen || !!q || junctions.includes(state.selectedNode);
    const li = document.createElement('li');
    li.className = 'place' + (open ? ' open' : ''); li.tabIndex = 0; li.setAttribute('aria-expanded', open);
    li.innerHTML = `<i class="c-junction"></i><span class="placeText"><strong>Waypoints</strong><span>${junctions.length} junction${junctions.length === 1 ? '' : 's'}</span></span>${ICON.chevron}`;
    li.onclick = () => { state.waypointsOpen = !open; renderPlaces(); };
    li.onkeydown = e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); li.onclick(); } };
    ul.appendChild(li);
    if (open) junctions.forEach(p => ul.appendChild(placeRow(p, degree, true)));
  }
  if (!named.length && !junctions.length) ul.innerHTML = '<li class="empty">No place matches.</li>';
}

function placeRow(p, degree, sub = false) {
  const li = document.createElement('li');
  li.className = 'place' + (sub ? ' sub' : '') + (p === state.selectedNode ? ' active' : '');
  li.tabIndex = 0;
  const d = degree.get(p.id) || 0;
  li.innerHTML = `<i style="background:${colorOf(p)}"></i><span class="placeText"><strong></strong><span>${p.category || 'destination'} · ${d} connection${d === 1 ? '' : 's'}</span></span>`;
  li.querySelector('strong').textContent = p.name;
  li.onclick = () => { selectNode(p); ensureVisible(p); };
  li.onkeydown = e => { if (e.key === 'Enter') li.onclick(); };
  return li;
}

const SOURCES = { ios: ['iPhone', ICON_PHONE], android: ['Android', ICON_PHONE], web: ['Web', ''] };
function renderVersions() {
  const ul = $('versions'); ul.replaceChildren();
  $('historyCount').textContent = state.versions.length || '';
  if (!state.versions.length) { ul.innerHTML = '<li class="empty">Not published yet.</li>'; return; }
  const liveId = state.versions[0].id;
  state.versions.forEach(v => {
    const li = document.createElement('li');
    const open = state.current?.id === v.id;
    li.className = 'version' + (open ? ' active' : ''); li.tabIndex = 0;
    const [label, icon] = SOURCES[v.source] || [v.source || '?', ''];
    const tag = v.id === liveId ? '<span class="live"><i></i>Live</span>' : open ? '' : '<span class="vOpen">Open</span>';
    li.innerHTML = `<div class="vHead"><strong>v${v.version}</strong><span class="src ${escapeHTML(v.source || '')}">${icon}${escapeHTML(label)}</span><span class="grow"></span>${tag}</div>`
      + (v.note ? `<p>${escapeHTML(v.note)}</p>` : '')
      + `<span class="vMeta">${dateTime(v.created_at)} · ${v.node_count ?? 0} places${v.point_count ? ` · ${fmtInt(v.point_count)} pts` : ''}</span>`;
    li.onclick = () => { if (!open) loadVersion(v); };
    li.onkeydown = e => { if (e.key === 'Enter') li.onclick(); };
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

// ---------- right rail: Map, Edit place, Connection ----------
const TYPE_HINTS = {
  destination: () => 'Destination — visitors can ask to be guided here.',
  junction: () => 'Junction — for routing only; never announced or offered as a destination.',
  exhibit: n => `Exhibit — navigable, and the description is spoken automatically within ${announceRadius(n)} m.`,
  hazard: n => `Hazard — announced with a warning haptic within ${announceRadius(n)} m.`,
};
function renderType(n) {
  const cat = n.category || 'destination';
  document.querySelectorAll('#typeGrid [data-cat]').forEach(b => {
    const on = b.dataset.cat === cat;
    b.setAttribute('aria-checked', on);
    if (!b.querySelector('.ic')) b.insertAdjacentHTML('afterbegin', ICON.check);
  });
  $('typeHint').dataset.cat = cat; $('typeHint').textContent = (TYPE_HINTS[cat] || TYPE_HINTS.destination)(n);
  renderRadius(n);
  $('nodeExplore').hidden = cat !== 'exhibit';
}

function renderAliases(n) {
  const box = $('aliasChips'), input = $('aliasInput');
  box.querySelectorAll('.alias').forEach(c => c.remove());
  (n.aliases || []).forEach((a, i) => {
    const b = document.createElement('button'); b.className = 'alias'; b.title = `Remove “${a}”`;
    b.textContent = a; b.insertAdjacentHTML('beforeend', ICON.x);
    b.onclick = () => { beginChange(); n.aliases.splice(i, 1); markDirty(); };
    box.insertBefore(b, input);
  });
}

function renderNodeEdges(n) {
  const ul = $('nodeEdges'); ul.replaceChildren();
  const g = state.graph;
  const linked = g.edges.map((e, i) => ({ e, i })).filter(({ e }) => e.from === n.id || e.to === n.id);
  if (!linked.length) { ul.innerHTML = '<li class="empty">Not connected yet. Use <b>Connect</b> or <b>Path</b>.</li>'; return; }
  for (const { e } of linked) {
    const other = nodeById(e.from === n.id ? e.to : e.from);
    const li = document.createElement('li'); li.className = 'conn';
    li.innerHTML = `<i style="background:${other ? colorOf(other) : '#555'}"></i><button class="connName"></button><span class="mono">${other ? Math.hypot(other.x - n.x, other.z - n.z).toFixed(1) + ' m' : ''}</span><button class="x" aria-label="Remove connection">${ICON.x}</button>`;
    li.querySelector('.connName').textContent = other?.name ?? '?';
    li.querySelector('.connName').onclick = () => { if (other) { selectNode(other); ensureVisible(other); } };
    li.querySelector('.x').onclick = () => {
      beginChange(); const k = state.graph.edges.indexOf(e); if (k >= 0) state.graph.edges.splice(k, 1); markDirty();
    };
    ul.appendChild(li);
  }
}

function renderInspector() {
  const g = state.graph, n = state.selectedNode, ei = state.selectedEdge;
  $('mapPanel').hidden = !g || !!n || ei !== null;
  $('nodePanel').hidden = !n; $('edgePanel').hidden = ei === null;
  if (g) {
    if (document.activeElement !== $('mapName')) $('mapName').value = g.name ?? '';
    $('mapSlug').textContent = state.slug;
    const named = g.pois.filter(p => p.category !== 'junction').length;
    $('mapStats').textContent = `${named} place${named === 1 ? '' : 's'} · ${g.pois.length - named} waypoint${g.pois.length - named === 1 ? '' : 's'} · ${g.edges.length} connection${g.edges.length === 1 ? '' : 's'}`;
    renderExploreMap(g);
  }
  if (n) {
    $('nodeId').textContent = n.id;
    if (document.activeElement !== $('nodeName')) $('nodeName').value = n.name;
    if (document.activeElement !== $('nodeDetails')) $('nodeDetails').value = n.details || '';
    $('nodeX').value = n.x.toFixed(2); $('nodeZ').value = n.z.toFixed(2);
    renderType(n); renderAliases(n); renderNodeEdges(n);
    for (const [id, key] of NODE_EXPLORE_FIELDS) if (document.activeElement !== $(id)) $(id).value = ExploreFields.fieldValue(n, key);
  }
  if (ei !== null) {
    const e = g.edges[ei], a = nodeById(e.from), b = nodeById(e.to);
    $('edgeLabel').textContent = `${a?.name ?? e.from} ↔ ${b?.name ?? e.to}`;
    $('edgeLength').textContent = a && b ? `${Math.hypot(a.x - b.x, a.z - b.z).toFixed(2)} m` : '';
  }
}

function renderMobileBar() {
  const n = state.selectedNode, ei = state.selectedEdge, g = state.graph;
  $('mbEdit').hidden = !n && ei === null;
  if (n) {
    $('mbDot').style.background = colorOf(n); $('mbName').textContent = n.name;
    $('mbMeta').textContent = `${n.category || 'destination'} · x ${fmtCoord(n.x)} z ${fmtCoord(n.z)}`;
  } else if (ei !== null && g) {
    const e = g.edges[ei], a = nodeById(e.from), b = nodeById(e.to);
    $('mbDot').style.background = '#C8C2DC'; $('mbName').textContent = `${a?.name ?? '?'} ↔ ${b?.name ?? '?'}`;
    $('mbMeta').textContent = a && b ? `connection · ${Math.hypot(a.x - b.x, a.z - b.z).toFixed(1)} m` : 'connection';
  } else {
    $('mbDot').style.background = 'transparent'; $('mbName').textContent = g?.name || state.slug;
    $('mbMeta').textContent = { select: 'tap a place to select it', add: 'tap the map to add a place', connect: 'tap two places to connect them', path: 'tap along the corridor · tap a place to end', cloud: 'drag to move the scan' }[state.mode];
  }
}

function renderHeader() {
  const g = state.graph, cur = state.current, live = state.versions[0];
  $('chipName').textContent = g?.name || state.slug;
  let status, sub;
  if (state.loading) { status = 'new'; sub = 'loading…'; }
  else if (state.dirty) { status = 'editing'; sub = cur ? `v${cur.version} · editing` : 'new · editing'; }
  else if (!cur) { status = 'new'; sub = 'not published'; }
  else if (live && cur.id === live.id) { status = 'live'; sub = `v${cur.version} · live`; }
  else { status = 'old'; sub = `v${cur.version} · not live`; }
  $('mapChip').dataset.status = status; $('chipSub').textContent = sub;
  $('publish').disabled = !g;
  renderPublishLabel();
  const n = state.dirty ? changeCount() : 0;
  $('unsaved').hidden = !state.dirty;
  $('unsavedText').textContent = n ? `${n} unpublished change${n === 1 ? '' : 's'}` : 'Unpublished changes';
  document.title = g ? `${g.name || state.slug} · AISEE-BIN Map Editor` : 'AISEE-BIN Map Editor';
}
const nextVersion = () => (state.versions[0]?.version ?? 0) + 1;
function renderPublishLabel() {
  const narrow = isNarrow();
  $('publishLabel').textContent = narrow ? 'Publish' : `Publish v${nextVersion()}`;
  $('publishConfirmLabel').textContent = `Publish v${nextVersion()}`;
}

function renderFooterRight() {
  const el = $('footRight');
  el.textContent = document.body.dataset.view === 'editor' && state.draftSavedAt ? `draft autosaved ${timeOnly(state.draftSavedAt)}` : '';
}

function renderFiles() {
  const row = state.current;
  for (const [id, path] of [['downloadWorldMap', row?.worldmap_path], ['downloadPoints', row?.pointcloud_path]]) {
    const a = $(id);
    if (path) { a.href = publicURL(path); a.classList.remove('disabled'); a.removeAttribute('aria-disabled'); }
    else { a.removeAttribute('href'); a.classList.add('disabled'); a.setAttribute('aria-disabled', 'true'); }
  }
  $('worldMapSize').textContent = row?.worldmap_path ? (worldMapSizes.get(row.worldmap_path) ?? '') : 'none';
}
const worldMapSizes = new Map();
/// The world map can be tens of MB, so the menu says how big before anyone clicks.
async function fetchWorldMapSize() {
  const path = state.current?.worldmap_path; if (!path || worldMapSizes.has(path)) return;
  try {
    const res = await fetch(publicURL(path), { method: 'HEAD' });
    const bytes = +res.headers.get('content-length');
    if (res.ok && bytes) worldMapSizes.set(path, `${(bytes / 1e6).toFixed(1)} MB`);
  } catch {}
  renderFiles();
}

function renderSidebar() {
  renderPlaces(); renderInspector(); renderConnectivity(); renderClouds(); renderMobileBar(); renderHeader();
}

function markDirty() { state.dirty = true; updateSaveButton(); renderSidebar(); draw(); }
function updateSaveButton() { renderHeader(); if (state.dirty) scheduleDraft(); }
function setStatus(text, isError = false, busy = false) {
  $('status').textContent = text;
  $('statusBar').className = 'statusBar' + (isError ? ' error' : busy ? ' busy' : '');
}
function escapeHTML(s) { return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

function selectNode(n) { state.selectedNode = n; state.selectedEdge = null; renderSidebar(); draw(); }
function selectEdge(i) { state.selectedEdge = i; state.selectedNode = null; renderSidebar(); draw(); }

/// Pans so a place picked from a list is on screen (it may be off to one side).
function ensureVisible(p) {
  const [x, y] = toScreen(p.x, p.z), w = canvas.clientWidth, h = canvas.clientHeight, m = 60;
  if (x >= m && y >= m && x <= w - m && y <= h - m) return;
  state.view.ox += w / 2 - x; state.view.oy += h / 2 - y; draw();
}

const HINTS = {
  select: 'drag to pan · wheel to zoom · drag a place to move it · ⌦ delete · ⌘Z undo',
  add: 'click the map to add a place · Esc to stop',
  connect: 'click a place, then another, to connect them (or remove their connection)',
  cloud: 'drag to move the selected scan · Alt/Option-drag to turn it · arrows nudge 10 cm (Shift 1 m) · [ ] turn 1° (Shift 5°) · Esc to stop',
};
function setMode(mode) {
  state.mode = mode; state.connectFrom = null;
  state.pathFrom = mode === 'path' ? state.selectedNode : null;
  document.querySelectorAll('[data-mode]').forEach(b => { b.classList.toggle('active', b.dataset.mode === mode); if (b.closest('.seg, .mbTools')) b.setAttribute('aria-pressed', b.dataset.mode === mode); });
  $('moveCloud').classList.toggle('active', mode === 'cloud');
  canvas.className = mode === 'select' ? '' : mode === 'cloud' ? 'dragging' : mode;
  setModeHint();
  renderMobileBar();
  draw();
}

function setModeHint() {
  $('hint').textContent = state.mode === 'path'
    ? (state.pathFrom ? `Path from “${state.pathFrom.name}”: ` : 'Path: click a place to start, then ') + 'click along the corridor to lay waypoints · click a place to end there · Esc to stop'
    : HINTS[state.mode];
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
  const count = state.graph.pois.filter(p => p.category !== 'junction').length + 1;
  const node = { id: uniqueId('node'), name: `Place ${count}`, x: +x.toFixed(2), z: +z.toFixed(2), category: 'destination', details: null, aliases: [] };
  state.graph.pois.push(node); selectNode(node); markDirty(); setMode('select');
  if (isNarrow()) openSheet('right');
  // After this pointerdown the canvas's mousedown would take focus back; focus after it.
  else setTimeout(() => { $('nodeName').focus(); $('nodeName').select(); }, 0);
}

function handlePathClick(node, sx, sy) {
  if (node) {
    if (state.pathFrom && state.pathFrom !== node) toggleEdgeEnsure(state.pathFrom, node);
    state.pathFrom = node; selectNode(node); setModeHint();
  } else {
    const [x, z] = toWorld(sx, sy); const wp = addWaypointAt(x, z);
    if (state.pathFrom) toggleEdgeEnsure(state.pathFrom, wp);
    else setStatus('Path started on empty map: end it on a place, or it stays disconnected.');
    state.pathFrom = wp; selectNode(wp); markDirty(); setModeHint();
  }
}

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

// ---------- canvas input ----------
// One pointer pans, drags or edits by mode; two pointers (touch) pinch-zoom.
const pointers = new Map();
const localPoint = ev => { const r = canvas.getBoundingClientRect(); return [ev.clientX - r.left, ev.clientY - r.top]; };

function startPinch() {
  const [a, b] = [...pointers.values()];
  const mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  // A place dragged by the first finger snaps back: the second finger meant zoom.
  if (state.drag?.type === 'node' && state.drag.moved) { restoreSnapshotQuiet(state.drag.snap); }
  state.drag = { type: 'pinch', d: Math.hypot(a[0] - b[0], a[1] - b[1]) || 1, scale: state.view.scale, world: toWorld(...mid) };
}
function restoreSnapshotQuiet(snap) {
  const id = state.selectedNode?.id; state.graph = JSON.parse(snap); state.selectedNode = id ? nodeById(id) : null; renderSidebar(); draw();
}

canvas.addEventListener('pointerdown', ev => {
  if (!state.graph) return;
  const [sx, sy] = localPoint(ev);
  canvas.setPointerCapture(ev.pointerId);
  pointers.set(ev.pointerId, [sx, sy]);
  if (pointers.size === 2) { startPinch(); return; }
  if (pointers.size > 2) return;
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
  const tol = ev.pointerType === 'touch' ? 22 : 12;
  const node = hitNode(sx, sy, tol);
  if (state.mode === 'add') { if (!node) { const [x, z] = toWorld(sx, sy); addNodeAt(x, z); } return; }
  if (state.mode === 'path') {
    // Snap to an existing place within 1 m so waypoints laid next to a place attach to it.
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
  if (node) { selectNode(node); state.drag = { type: 'node', node, moved: false, snap: snapshot(), x: sx, y: sy }; return; }
  const edge = hitEdge(sx, sy, ev.pointerType === 'touch' ? 12 : 6);
  if (edge !== null) { selectEdge(edge); return; }
  if (state.selectedNode || state.selectedEdge !== null) { state.selectedNode = null; state.selectedEdge = null; renderSidebar(); draw(); }
  state.drag = { type: 'pan', x: sx, y: sy, ox: state.view.ox, oy: state.view.oy };
  canvas.classList.add('dragging');
});

canvas.addEventListener('pointermove', ev => {
  const [sx, sy] = localPoint(ev);
  const [wx, wz] = toWorld(sx, sy); $('coords').textContent = `x ${fmtCoord(wx)}   z ${fmtCoord(wz)}`;
  if (pointers.has(ev.pointerId)) pointers.set(ev.pointerId, [sx, sy]);
  const d = state.drag; if (!d) return;
  if (d.type === 'pinch') {
    if (pointers.size < 2) return;
    const [a, b] = [...pointers.values()];
    const mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    state.view.scale = Math.max(3, Math.min(300, d.scale * Math.hypot(a[0] - b[0], a[1] - b[1]) / d.d));
    state.view.ox = mid[0] - d.world[0] * state.view.scale; state.view.oy = mid[1] - d.world[1] * state.view.scale;
    draw();
  } else if (d.type === 'pan') { state.view.ox = d.ox + sx - d.x; state.view.oy = d.oy + sy - d.y; draw(); }
  else if (d.type === 'cloud') { dragCloud(wx, wz); }
  else {
    // A few pixels of slop so a tap that wobbles does not move the place.
    if (!d.moved && Math.hypot(sx - d.x, sy - d.y) < (ev.pointerType === 'touch' ? 8 : 3)) return;
    d.node.x = +wx.toFixed(2); d.node.z = +wz.toFixed(2); d.moved = true; renderInspector(); renderMobileBar(); draw();
  }
});

function endPointer(ev) {
  pointers.delete(ev.pointerId);
  if (state.drag?.type === 'pinch') { if (pointers.size === 0) state.drag = null; return; }
  if ((state.drag?.type === 'node' || state.drag?.type === 'cloud') && state.drag.moved) {
    // Record the pre-drag state as one undo step.
    state.history.push(state.drag.snap); if (state.history.length > 200) state.history.shift();
    state.future = []; updateUndoButtons();
    markDirty();
  }
  const wasCloud = state.drag?.type === 'cloud';
  state.drag = null; if (state.mode !== 'cloud') canvas.classList.remove('dragging');
  if (wasCloud) { renderCloudEdit(); scheduleOverlap(); }
}
canvas.addEventListener('pointerup', endPointer);
canvas.addEventListener('pointercancel', endPointer);
canvas.addEventListener('contextmenu', ev => ev.preventDefault());
canvas.addEventListener('auxclick', ev => ev.preventDefault());

canvas.addEventListener('wheel', ev => {
  ev.preventDefault();
  const [sx, sy] = localPoint(ev);
  const [wx, wz] = toWorld(sx, sy);
  state.view.scale = Math.max(3, Math.min(300, state.view.scale * (ev.deltaY < 0 ? 1.12 : 1 / 1.12)));
  state.view.ox = sx - wx * state.view.scale; state.view.oy = sy - wz * state.view.scale;
  draw();
}, { passive: false });

document.addEventListener('keydown', ev => {
  if ($('publishDialog').open || !$('view3d').hidden || document.body.dataset.view !== 'editor') return;
  if (ev.key === 'Escape' && (openMenuId || document.body.classList.contains('sheet-left') || document.body.classList.contains('sheet-right'))) { closeMenus(); closeSheets(); return; }
  const mod = ev.metaKey || ev.ctrlKey;
  const typing = ['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement.tagName);
  if (mod && ev.key.toLowerCase() === 'z' && !typing) { ev.preventDefault(); ev.shiftKey ? redo() : undo(); return; }
  if (mod && ev.key.toLowerCase() === 'y' && !typing) { ev.preventDefault(); redo(); return; }
  if (typing) return;
  if (state.mode === 'cloud' && placementOf(state.selectedCloud)) {
    const m = ev.shiftKey ? 1 : 0.1, deg = ev.shiftKey ? 5 : 1;
    const moves = { ArrowLeft: [-m, 0, 0], ArrowRight: [m, 0, 0], ArrowUp: [0, -m, 0], ArrowDown: [0, m, 0], '[': [0, 0, -deg], ']': [0, 0, deg], '{': [0, 0, -deg], '}': [0, 0, deg] };
    const mv = moves[ev.key];
    if (mv) { ev.preventDefault(); nudgeCloud(mv[0], mv[1], mv[2]); return; }
  }
  if (ev.key === 'Escape') { setMode('select'); selectNode(null); }
  if ((ev.key === 'Delete' || ev.key === 'Backspace') && !ev.target.closest?.('.menu')) { if (state.selectedNode) deleteNode(); else if (state.selectedEdge !== null) deleteEdge(); }
});

function deleteNode() {
  const n = state.selectedNode; if (!n || !confirm(`Delete “${n.name}” and its connections?`)) return;
  beginChange();
  state.graph.pois = state.graph.pois.filter(p => p !== n);
  state.graph.edges = state.graph.edges.filter(e => e.from !== n.id && e.to !== n.id);
  state.selectedNode = null; closeSheets(); markDirty();
}
function deleteEdge() { if (state.selectedEdge === null) return; beginChange(); state.graph.edges.splice(state.selectedEdge, 1); state.selectedEdge = null; closeSheets(); markDirty(); }

// ---------- inspector bindings ----------
['nodeName', 'nodeDetails', 'nodeX', 'nodeZ', 'nodeRadius', 'nodeRadiusRange', 'mapName'].forEach(id => $(id).addEventListener('focus', beginChange));
const bindNode = (id, apply) => $(id).addEventListener('input', () => {
  const n = state.selectedNode; if (!n) return;
  apply(n, $(id).value); state.dirty = true; updateSaveButton(); renderPlaces(); renderMobileBar(); draw();
});
bindNode('nodeName', (n, v) => n.name = v);
bindNode('nodeRadius', (n, v) => { setRadius(n, v); renderType(n); });
bindNode('nodeRadiusRange', (n, v) => { setRadius(n, v); renderType(n); });
// The slider can be dragged without focusing first; snapshot for undo on press.
$('nodeRadiusRange').addEventListener('pointerdown', beginChange);
$('nodeRadius').addEventListener('change', () => { if (state.selectedNode) renderRadius(state.selectedNode); });
$('nodeRadiusReset').onclick = () => {
  const n = state.selectedNode; if (!n) return;
  beginChange(); delete n.announceRadius; markDirty();
};
bindNode('nodeDetails', (n, v) => n.details = v || null);
bindNode('nodeX', (n, v) => { if (!isNaN(parseFloat(v))) n.x = parseFloat(v); });
bindNode('nodeZ', (n, v) => { if (!isNaN(parseFloat(v))) n.z = parseFloat(v); });
document.querySelectorAll('#typeGrid [data-cat]').forEach(b => b.onclick = () => {
  const n = state.selectedNode; if (!n || n.category === b.dataset.cat) return;
  beginChange(); n.category = b.dataset.cat; markDirty();
});
$('playDetails').onclick = () => {
  const n = state.selectedNode; if (!n || !window.speechSynthesis) return;
  speechSynthesis.cancel();
  speechSynthesis.speak(new SpeechSynthesisUtterance([n.name, n.details].filter(Boolean).join('. ')));
};
function addAliases() {
  const n = state.selectedNode, input = $('aliasInput'); if (!n) return;
  const add = input.value.split(',').map(s => s.trim()).filter(s => s && !(n.aliases || []).includes(s));
  input.value = '';
  if (!add.length) return;
  beginChange(); n.aliases = [...(n.aliases || []), ...add]; markDirty(); $('aliasInput').focus();
}
$('aliasInput').addEventListener('keydown', ev => {
  if (ev.key === 'Enter' || ev.key === ',') { ev.preventDefault(); addAliases(); }
  else if (ev.key === 'Backspace' && !ev.target.value && state.selectedNode?.aliases?.length) { beginChange(); state.selectedNode.aliases.pop(); markDirty(); $('aliasInput').focus(); }
});
$('aliasInput').addEventListener('blur', addAliases);
$('mapName').addEventListener('input', () => { if (state.graph) { state.graph.name = $('mapName').value; state.dirty = true; updateSaveButton(); renderMapMenu(); } });
// Explore fields (web/explore.js): empty inputs remove the key.
const NODE_EXPLORE_FIELDS = [['nodeMinutes', 'minutes'], ['nodeHighlight', 'highlight'], ['nodeTags', 'tags'], ['nodeAbout', 'about'], ['nodePhoto', 'photo']];
const MAP_EXPLORE_FIELDS = [['mapTourStart', 'tourStart'], ['mapTourEnd', 'tourEnd'], ['mapVenueInfo', 'venueInfo']];
function renderExploreMap(g) {
  $('explorePanel').hidden = !g;
  if (!g) return;
  const places = g.pois.filter(p => p.category !== 'junction').sort((a, b) => a.name.localeCompare(b.name));
  for (const id of ['mapTourStart', 'mapTourEnd']) {
    if (document.activeElement === $(id)) continue;
    $(id).replaceChildren(new Option('—', ''), ...places.map(p => new Option(p.name, p.id)));
  }
  for (const [id, key] of MAP_EXPLORE_FIELDS) if (document.activeElement !== $(id)) $(id).value = ExploreFields.fieldValue(g, key);
}
for (const [id, key] of NODE_EXPLORE_FIELDS) {
  $(id).addEventListener('focus', beginChange);
  bindNode(id, (n, v) => ExploreFields.applyField(n, key, v));
}
for (const [id, key] of MAP_EXPLORE_FIELDS) {
  $(id).addEventListener('focus', beginChange);
  $(id).addEventListener('input', () => {
    if (!state.graph) return;
    ExploreFields.applyField(state.graph, key, $(id).value);
    state.dirty = true; updateSaveButton();
  });
}

$('deleteNode').onclick = deleteNode;
$('autoConnect').onclick = autoConnectIsolated;
$('deleteEdge').onclick = deleteEdge;

document.querySelectorAll('[data-mode]').forEach(b => b.addEventListener('click', () => { closeMenus(); setMode(b.dataset.mode); }));
$('fit').onclick = $('fitFloat').onclick = () => { fitView(); draw(); };
$('undo').onclick = $('mmUndo').onclick = () => { undo(); closeMenus(); };
$('redo').onclick = $('mmRedo').onclick = () => { redo(); closeMenus(); };
['showPoints', 'showLabels', 'showDistances'].forEach(id => $(id).onchange = draw);
$('showLegend').onchange = () => { $('legend').hidden = !$('showLegend').checked; };
$('tabPlaces').onclick = () => setTab('places');
$('tabHistory').onclick = () => setTab('history');
$('placeSearch').addEventListener('input', renderPlaces);
$('mapSearch').addEventListener('input', renderHome);
$('refreshMaps').onclick = () => loadMaps().catch(e => setStatus(`Could not load maps: ${e.message}`, true));
$('checkVersions').onclick = async () => {
  closeMenus();
  try { await fetchVersions(); setStatus(`${state.versions.length} version(s); v${state.versions[0]?.version ?? '–'} is live.`); }
  catch (e) { setStatus(e.message, true); }
};

// ---------- menus and sheets ----------
let openMenuId = null;
const isNarrow = () => matchMedia('(max-width: 760px)').matches;
function openMenu(id, anchor) {
  const wasOpen = openMenuId === id;
  closeMenus();
  if (wasOpen) return;
  const m = $(id); m.hidden = false; openMenuId = id;
  anchor?.setAttribute('aria-expanded', 'true');
  if (isNarrow()) { m.style.top = m.style.left = ''; $('scrim').hidden = false; }
  else if (anchor) {
    const r = anchor.getBoundingClientRect();
    m.style.top = `${r.bottom + 8}px`;
    m.style.left = `${Math.max(12, Math.min(r.left, innerWidth - m.offsetWidth - 12))}px`;
  }
  if (id === 'mapMenu') renderMapMenu();
  if (id === 'filesMenu') { renderFiles(); fetchWorldMapSize(); }
  m.querySelector('button:not(:disabled), a:not(.disabled), input')?.focus({ preventScroll: true });
}
function closeMenus() {
  document.querySelectorAll('.menu').forEach(m => { m.hidden = true; });
  document.querySelectorAll('[data-menu][aria-expanded]').forEach(b => b.setAttribute('aria-expanded', 'false'));
  openMenuId = null;
  if (!document.body.className.includes('sheet-')) $('scrim').hidden = true;
}
function openSheet(side) {
  if (!isNarrow()) return;
  closeMenus(); document.body.classList.remove('sheet-left', 'sheet-right');
  document.body.classList.add(`sheet-${side}`); $('scrim').hidden = false;
}
function closeSheets() { document.body.classList.remove('sheet-left', 'sheet-right'); if (!openMenuId) $('scrim').hidden = true; }

document.querySelectorAll('[data-menu]').forEach(b => b.addEventListener('click', ev => { ev.stopPropagation(); openMenu(b.dataset.menu, b); }));
// A click outside an open menu closes it, and does not also act on the map.
document.addEventListener('pointerdown', ev => {
  if (!openMenuId || ev.target.closest('.menu, [data-menu]')) return;
  closeMenus();
  if (ev.target === canvas) ev.stopPropagation();
}, true);
document.addEventListener('keydown', ev => { if (ev.key === 'Escape' && openMenuId) closeMenus(); });
$('scrim').onclick = () => { closeMenus(); closeSheets(); };
document.querySelectorAll('[data-close-sheet]').forEach(b => b.onclick = closeSheets);
$('mbEdit').onclick = () => openSheet('right');
$('mmPlaces').onclick = () => openSheet('left');
$('mmMap').onclick = () => { selectNode(null); openSheet('right'); };
$('mmView').onclick = () => openMenu('viewMenu');
$('mmFiles').onclick = () => openMenu('filesMenu');
// Picking a place from the list on a phone shows it on the map.
$('placeList').addEventListener('click', ev => { if (ev.target.closest('.place:not([aria-expanded])')) closeSheets(); });
window.addEventListener('resize', () => { if (!isNarrow()) { closeSheets(); } renderPublishLabel(); });

// ---------- publish ----------
function openPublish() {
  if (!state.graph) return;
  closeMenus(); closeSheets(); saveDraftNow();
  renderPublish();
  $('publishError').hidden = true;
  $('publishDialog').showModal();
  if (isNarrow()) $('publishClose').focus(); else $('note').focus();   // no keyboard popping over the checks on a phone
}

function renderPublish() {
  const g = state.graph, base = state.current?.graph, live = state.versions[0];
  $('publishTitle').textContent = `Publish ${g.name || state.slug} v${nextVersion()}?`;
  const delta = (now, before) => { if (before == null) return ''; const d = now - before; return d ? ` <span class="${d > 0 ? 'up' : 'down'}">${d > 0 ? '+' : '−'}${Math.abs(d)}</span>` : ''; };
  const exhibits = g.pois.filter(p => p.category === 'exhibit');
  const named = g.pois.filter(p => p.category !== 'junction').length;
  const baseNamed = base ? (base.pois || []).filter(p => p.category !== 'junction').length : null;
  const baseExhibits = base ? (base.pois || []).filter(p => p.category === 'exhibit').length : null;
  $('publishStats').innerHTML =
    `<span><strong>${named}</strong><small>places${delta(named, baseNamed)}</small></span>` +
    `<span><strong>${exhibits.length}</strong><small>exhibits${delta(exhibits.length, baseExhibits)}</small></span>` +
    `<span><strong>${g.edges.length}</strong><small>connections${delta(g.edges.length, base ? (base.edges || []).length : null)}</small></span>`;

  // Warnings explain what visitors would get; none of them block publishing.
  const ul = $('publishChecks'); ul.replaceChildren();
  const row = (ok, text, actions = []) => {
    const li = document.createElement('li'); li.className = ok ? 'ok' : 'warn';
    li.innerHTML = `${ok ? ICON.check : ICON.warn}<span></span>`;
    li.querySelector('span').textContent = text;
    for (const [label, fn, cls] of actions) { const b = document.createElement('button'); b.className = cls || 'link'; b.textContent = label; b.onclick = fn; li.appendChild(b); }
    ul.appendChild(li);
  };
  const fix = p => () => { $('publishDialog').close(); setTab('places'); selectNode(p); ensureVisible(p); if (isNarrow()) openSheet('right'); };
  if (!named) row(false, 'This map has no places yet, so there is nowhere to guide visitors.');
  if (exhibits.length) {
    const silent = exhibits.filter(p => !(p.details || '').trim());
    if (!silent.length) row(true, 'Every exhibit has a description');
    else row(false, silent.length === 1 ? `“${silent[0].name}” has no spoken description` : `${silent.length} exhibits have no spoken description`, [['Fix', fix(silent[0])]]);
  }
  const isolated = isolatedPlaces();
  if (named && !isolated.length) row(true, 'Every place can be reached');
  isolated.slice(0, 3).forEach(p => row(false, `“${p.name}” isn’t connected to the route`, [['Fix', fix(p)], ['Auto-connect', () => { autoConnectIsolated(); renderPublish(); }, 'link warnLink']]));
  if (isolated.length > 3) row(false, `…and ${isolated.length - 3} more not connected`, [['Auto-connect all', () => { autoConnectIsolated(); renderPublish(); }, 'link warnLink']]);
  if (state.current && live && state.current.id !== live.id) row(false, `These edits start from v${state.current.version}, but v${live.version} is live. Publishing replaces what changed since.`);
  if (!state.dirty && state.current && live && state.current.id === live.id) row(true, `No changes since v${live.version}; this publishes the same map again.`);
  renderPublishLabel();
}

$('publish').onclick = openPublish;
$('publishConfirm').onclick = publishVersion;
$('keepEditing').onclick = $('publishClose').onclick = () => $('publishDialog').close();

// ---------- new maps: Immersal import and empty ----------
// Opens a finished Immersal scan as a new map. The route is then drawn straight
// in Immersal's coordinates and saved with an identity alignment to that map id,
// so the app and the glasses can use it without an alignment walk.
$('importImmersal').onclick = async () => {
  if (!leaveMapOk()) return;
  const idText = prompt('Immersal map id (from the Mapper app or the Developer Portal):', '');
  if (idText === null || !idText.trim()) return;
  const btn = $('importImmersal'); btn.disabled = true;
  try {
    setStatus(`Fetching Immersal map ${idText.trim()}…`, false, true);
    // The site's own proxy adds the account token server side; nothing to type.
    const map = await ImmersalImport.fetchMap({ id: idText.trim(), base: '/immersal' });
    const name = (prompt(`Name for this map (it becomes the server key and what the app calls it):`, map.name) || '').trim();
    if (!name) { setStatus('Import cancelled.'); return; }
    map.name = name;
    const slug = ImmersalImport.slugFromName(map.name) || `immersal-${map.id}`;
    const taken = state.maps.some(m => m.map_slug === slug);
    if (taken && !confirm(`A map called "${slug}" already exists on the server. Continue and publish the import as its next version?`)) return;
    resetMapState(slug);
    state.graph = { name: map.name, pois: [], edges: [], immersalAlignment: ImmersalImport.identityAlignment(map.id) };
    state.points = map.points; state.pendingPoints = map.points;
    computeHeights(); renderScanTools(); buildPointsBitmap();
    state.dirty = true;
    openMap(slug);
    // Versions are fetched for History and the next version number; the import itself stays as is.
    fetchVersions().catch(() => {});
    renderSidebar(); updateSaveButton(); fitView(); draw();
    setStatus(`Imported “${map.name}” (Immersal ${map.id}): ${fmtInt(map.points.length / 3)} points. Add places and paths, then publish.`);
  } catch (e) {
    setStatus(`Import failed: ${e.message}`, true);
  } finally { btn.disabled = false; }
};

$('newEmptyMap').onclick = () => {
  const name = (prompt('Name for the new map. Usually a map starts from a phone scan; an empty one suits a test graph or an imported JSON.', '') || '').trim();
  if (!name) return;
  const slug = name.toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-|-$/g, '');
  if (!slug) return;
  if (state.maps.some(m => m.map_slug === slug)) { if (confirm(`“${slug}” already exists. Open it?`)) openMap(slug); return; }
  if (!leaveMapOk()) return;
  resetMapState(slug);
  state.graph = { name, pois: [], edges: [] };
  openMap(slug);
  renderSidebar(); updateSaveButton(); fitView(); draw();
  setStatus(`New map “${name}”. Add places or import graph JSON, then publish.`);
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
  // While moving a scan it is drawn first and see-through, so the scans it is
  // being lined up against stay visible on top of it where they overlap.
  const moving = state.mode === 'cloud' ? state.selectedCloud : null;
  const order = [...state.clouds.values()].sort((a, b) => (b.id === moving) - (a.id === moving));
  for (const cl of order) {
    const pl = placementOf(cl.id); if (!pl || cl.hidden) continue;
    const selected = cl.id === moving;
    ctx.fillStyle = cl.color; ctx.globalAlpha = moving === null ? 0.6 : selected ? 0.35 : 0.8;
    const c = Math.cos(pl.yaw), s = Math.sin(pl.yaw), k = state.view.scale;
    const size = 1.5;
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
  if (!cl) { setStatus('That scan\'s point cloud has not loaded, so it cannot be moved yet.', true); return; }
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
  loadThree().then(() => { init3D(); rebuild3D(true); $('status3d').textContent = `${fmtInt(state.points.length / 3)} points · places shown as dots at floor height`; })
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
  closeMenus();
  if (!state.graph) return;
  const blob = new Blob([JSON.stringify(state.graph, null, 2)], { type: 'application/json' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `${state.slug}-v${state.current?.version ?? 'draft'}.map.json`; a.click();
};
$('importJSON').addEventListener('change', async ev => {
  closeMenus();
  const file = ev.target.files[0]; if (!file) return;
  try {
    const g = JSON.parse(await file.text());
    if (!Array.isArray(g.pois) || !Array.isArray(g.edges)) throw new Error('expected {name, pois, edges}');
    if (state.graph) beginChange(); else { state.history = []; state.future = []; }
    state.graph = g; state.selectedNode = state.selectedEdge = null; markDirty(); fitView(); draw();
    setStatus(`Imported ${g.pois.length} places from ${file.name}. Publish to make it live.`);
  } catch (e) { setStatus(`Import failed: ${e.message}`, true); }
  ev.target.value = '';
});
['downloadWorldMap', 'downloadPoints', 'open3d'].forEach(id => $(id).addEventListener('click', closeMenus));

// Drafts cover ordinary edits; only an unpublished Immersal import, or a draft
// the browser refused to store, is lost by closing the tab.
window.addEventListener('beforeunload', ev => {
  saveDraftNow();
  if (state.dirty && (state.pendingPoints || !state.draftSavedAt)) { ev.preventDefault(); ev.returnValue = ''; }
});
window.addEventListener('resize', resize);
window.addEventListener('hashchange', route);

// ---------- boot ----------
document.fonts?.ready.then(draw);
route();
if (document.body.dataset.view === 'editor') loadMaps().catch(() => {});
