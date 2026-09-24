// Immersal import for the map editor: fetch a scanned map's sparse point cloud
// and open it as a new route map drawn in Immersal's own coordinate frame.
//
// Plain script for the browser (exposes `ImmersalImport`) and a CommonJS module
// for the node tests. No DOM in here: app.js does the wiring.
(function (root) {
  'use strict';

  const API = 'https://api.immersal.com';

  /// Parses a binary little-endian PLY into consecutive Float32 x y z triples,
  /// the editor's point format. Extra per-vertex properties (colour, normals)
  /// are skipped; faces are ignored. Immersal's exports are always binary.
  function parsePLYPoints(buffer) {
    const bytes = new Uint8Array(buffer);
    const marker = new TextEncoder().encode('end_header\n');
    let headerEnd = -1;
    outer: for (let i = 0; i <= bytes.length - marker.length; i++) {
      for (let j = 0; j < marker.length; j++) if (bytes[i + j] !== marker[j]) continue outer;
      headerEnd = i + marker.length; break;
    }
    if (headerEnd < 0 || !(bytes[0] === 0x70 && bytes[1] === 0x6c && bytes[2] === 0x79)) throw new Error('not a PLY file');
    const header = new TextDecoder().decode(bytes.subarray(0, headerEnd)).split('\n');
    if (!header.some(l => l.startsWith('format binary_little_endian'))) throw new Error('only binary little-endian PLY is supported');

    const sizes = { char: 1, uchar: 1, int8: 1, uint8: 1, short: 2, ushort: 2, int16: 2, uint16: 2,
                    int: 4, uint: 4, int32: 4, uint32: 4, float: 4, float32: 4, double: 8, float64: 8 };
    let vertexCount = 0, inVertex = false, stride = 0;
    const offsets = {};
    for (const line of header) {
      const t = line.trim().split(/\s+/);
      if (t[0] === 'element') { inVertex = t[1] === 'vertex'; if (inVertex) vertexCount = parseInt(t[2], 10); continue; }
      if (t[0] !== 'property' || !inVertex) continue;
      if (t[1] === 'list') throw new Error('list properties on vertices are not supported');
      const size = sizes[t[1]]; if (!size) throw new Error(`unknown property type ${t[1]}`);
      if (t[2] === 'x' || t[2] === 'y' || t[2] === 'z') {
        if (t[1] !== 'float' && t[1] !== 'float32') throw new Error(`${t[2]} must be float32, got ${t[1]}`);
        offsets[t[2]] = stride;
      }
      stride += size;
    }
    if (offsets.x === undefined || offsets.y === undefined || offsets.z === undefined) throw new Error('vertices lack x y z');
    if (headerEnd + vertexCount * stride > bytes.length) throw new Error('PLY is truncated');

    const view = new DataView(buffer, headerEnd);
    const out = new Float32Array(vertexCount * 3);
    for (let i = 0, base = 0; i < vertexCount; i++, base += stride) {
      out[i * 3] = view.getFloat32(base + offsets.x, true);
      out[i * 3 + 1] = view.getFloat32(base + offsets.y, true);
      out[i * 3 + 2] = view.getFloat32(base + offsets.z, true);
    }
    return out;
  }

  /// The alignment an imported map carries: the graph *is* in Immersal's
  /// frame, so the transform is the identity and no walk ever fitted it.
  /// pairCount 0 is how the app tells this apart from a fitted alignment.
  function identityAlignment(mapId) {
    return { mapIDs: [mapId], yaw: 0, tx: 0, tz: 0, pairCount: 0, rmsError: 0 };
  }

  /// Same rule as the editor's "+ New map" and the app's `MapSyncService.slug`.
  function slugFromName(name) {
    return String(name || '').toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-|-$/g, '');
  }

  /// Looks the map up and downloads its sparse cloud.
  /// Resolves to { id, name, status, points } or throws with Immersal's reason.
  ///
  /// Two ways in. With a `token`, straight to Immersal (name and status come
  /// from /metadataget). With a `base` and no token, through the site's own
  /// read-only proxy, which adds the account token server side and only
  /// forwards the point cloud download, so the page never holds a token; the
  /// name is then a placeholder for the editor's Name field to replace.
  async function fetchMap({ id, token, base, fetch: fetchImpl = root.fetch }) {
    const mapId = parseInt(id, 10);
    if (!Number.isInteger(mapId) || mapId <= 0) throw new Error('map id must be a positive integer');
    if (!token) {
      if (!base) throw new Error('need a token or a proxy base');
      const res = await fetchImpl(`${base}/sparse?id=${mapId}`);
      // Immersal answers 400 for an unknown id and 404 for a map with no cloud yet.
      if (res.status === 400 || res.status === 404) throw new Error(`Immersal: map ${mapId} not found under the site's account, or not finished constructing`);
      if (!res.ok) throw new Error(`Immersal: sparse point cloud ${res.status} ${res.statusText}`);
      const points = parsePLYPoints(await res.arrayBuffer());
      if (!points.length) throw new Error('Immersal returned an empty point cloud');
      return { id: mapId, name: `Immersal ${mapId}`, status: 'done', points };
    }
    const metaRes = await fetchImpl(`${API}/metadataget`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, id: mapId }),
    });
    const meta = await metaRes.json().catch(() => ({ error: `${metaRes.status} ${metaRes.statusText}` }));
    if (meta.error && meta.error !== 'none') throw new Error(`Immersal: ${meta.error === 'not found' ? 'map not found under this token' : meta.error}`);
    if (meta.status && meta.status !== 'done') throw new Error(`Immersal map ${mapId} is "${meta.status}", not finished constructing`);
    const plyRes = await fetchImpl(`${API}/sparse?token=${encodeURIComponent(token)}&id=${mapId}`);
    if (!plyRes.ok) throw new Error(`Immersal: sparse point cloud ${plyRes.status} ${plyRes.statusText}`);
    const points = parsePLYPoints(await plyRes.arrayBuffer());
    if (!points.length) throw new Error('Immersal returned an empty point cloud');
    return { id: mapId, name: meta.name || `immersal-${mapId}`, status: meta.status, points };
  }

  const api = { parsePLYPoints, identityAlignment, slugFromName, fetchMap };
  root.ImmersalImport = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
