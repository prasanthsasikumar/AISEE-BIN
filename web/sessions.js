// Turns a session's ab_events rows into map path segments, fix markers, a human
// timeline and CSV, for the Sessions page. Pure functions, no DOM.
//
// Plain script for the browser (exposes `Sessions`) and a CommonJS module for
// the node tests.
(function (root) {
  'use strict';

  const GAP_MS = 10000;      // poses further apart than this are not joined
  const FIX_WINDOW_MS = 2000; // a loc.attempt takes the next pose within this

  const num = v => typeof v === 'number' && Number.isFinite(v);
  const time = e => Date.parse(e && e.t);
  const dat = e => (e && e.data && typeof e.data === 'object') ? e.data : {};

  function sortEvents(events) {
    return (events || []).slice().sort((a, b) => a.seq - b.seq);
  }

  function isPose(e) {
    const d = dat(e);
    return e.type === 'pose' && d.localized !== false && num(d.x) && num(d.z);
  }

  function pathSegments(events) {
    const segs = [];
    let cur = { slug: null, version: null, points: [] };
    let last = null;
    const flush = () => { if (cur.points.length) segs.push(cur); };
    for (const e of sortEvents(events)) {
      const d = dat(e);
      if (e.type === 'map.loaded') {
        flush();
        cur = { slug: d.slug ?? null, version: d.version ?? null, points: [] };
        last = null;
      } else if (isPose(e)) {
        const t = time(e);
        if (last !== null && Number.isFinite(t) && t - last > GAP_MS) {
          flush();
          cur = { slug: cur.slug, version: cur.version, points: [] };
        }
        cur.points.push({ x: d.x, z: d.z, t: e.t });
        if (Number.isFinite(t)) last = t;
      }
    }
    flush();
    return segs;
  }

  function fixMarkers(events) {
    const sorted = sortEvents(events);
    const out = [];
    sorted.forEach((e, i) => {
      if (e.type !== 'loc.attempt') return;
      const t0 = time(e);
      for (let j = i + 1; j < sorted.length; j++) {
        const p = sorted[j];
        const dt = time(p) - t0;
        if (dt > FIX_WINDOW_MS) break;
        if (isPose(p) && dt >= 0) {
          const d = dat(e);
          out.push({ x: dat(p).x, z: dat(p).z, t: e.t, ok: !!d.ok, accepted: d.accepted });
          break;
        }
      }
    });
    return out;
  }

  function duration(sec) {
    if (!num(sec)) return '?';
    const s = Math.round(sec);
    const m = Math.floor(s / 60);
    return m > 0 ? `${m} m ${s % 60} s` : `${s} s`;
  }

  const q = s => `“${s ?? ''}”`;
  const fixed = (v, n = 1) => num(v) ? v.toFixed(n) : '?';

  // names: to_id -> to_name from earlier nav.request rows, since nav.arrived and
  // nav.cancel carry only the id.
  function describe(e, names = new Map()) {
    const d = dat(e);
    const dest = () => names.get(d.to_id) ?? d.to_name ?? d.to_id;
    switch (e.type) {
      case 'speech.heard': return ['heard', `Heard: ${q(d.text)}`];
      case 'speech.said': return ['said', `Said: ${q(d.text)}`];
      case 'speech.intent': return ['heard', `Understood ${d.intent ?? '?'}${d.text ? ` from ${q(d.text)}` : ''}`];
      case 'nav.request': return ['nav', `Route requested to ${d.to_name ?? d.to_id ?? '?'}${num(d.path_m) ? ` (${fixed(d.path_m, 0)} m)` : ''}`];
      case 'nav.start': return ['nav', 'Navigation started'];
      case 'nav.off_route': return ['nav', `Off route${num(d.distance_m) ? ` by ${fixed(d.distance_m)} m` : ''}`];
      case 'nav.reroute': return ['nav', `Rerouted${num(d.path_m) ? ` (${fixed(d.path_m, 0)} m)` : ''}`];
      case 'nav.waypoint': return ['nav', `Passed waypoint ${d.id ?? ''}`.trim()];
      case 'nav.arrived': return ['nav', `Arrived at ${dest() ?? '?'} after ${duration(d.seconds)}${num(d.walked_m) ? `, walked ${fixed(d.walked_m, 0)} m` : ''}`];
      case 'nav.cancel': return ['nav', `Navigation${dest() != null ? ` to ${dest()}` : ''} cancelled${d.reason ? ` (${String(d.reason).replace(/_/g, ' ')})` : ''}${num(d.seconds) ? ` after ${duration(d.seconds)}` : ''}`];
      case 'mode.enter': return ['mode', `Entered ${d.mode ?? '?'} mode`];
      case 'mode.leave': return ['mode', `Left ${d.mode ?? '?'} mode${num(d.seconds) ? ` after ${duration(d.seconds)}` : ''}`];
      case 'loc.attempt': {
        const bits = [d.source, d.localizer].filter(Boolean).join(', ');
        const res = d.ok ? (d.accepted === false ? 'rejected' : 'fix') : `failed${d.error ? `: ${d.error}` : ''}`;
        return ['loc', `Localization ${res}${bits ? ` (${bits})` : ''}${num(d.ms) ? ` ${Math.round(d.ms)} ms` : ''}${num(d.jump_m) ? `, jump ${fixed(d.jump_m)} m` : ''}`];
      }
      case 'positioning.start': return ['loc', `Positioning started${d.source ? ` (${d.source})` : ''}`];
      case 'positioning.stop': return ['loc', `Positioning stopped${d.source ? ` (${d.source})` : ''}${num(d.fixes) ? `, ${d.fixes}/${d.attempts ?? '?'} fixes` : ''}`];
      case 'ar.tracking': return ['loc', `AR tracking ${d.state ?? '?'}${d.reason ? ` (${d.reason})` : ''}`];
      case 'glasses.connect': return ['loc', `Glasses connected${num(d.battery) ? `, battery ${d.battery}%` : ''}`];
      case 'glasses.disconnect': return ['loc', `Glasses disconnected${d.reason ? ` (${d.reason})` : ''}`];
      case 'explore.plan': return ['explore', `Tour planned${d.utterance ? ` from ${q(d.utterance)}` : ''}${d.ok === false ? ` failed${d.error ? `: ${d.error}` : ''}` : ''}`];
      case 'explore.ask': return ['explore', `Asked ${q(d.question)}${d.answer ? ` → ${q(d.answer)}` : ''}${d.ok === false ? ` failed${d.error ? `: ${d.error}` : ''}` : ''}`];
      case 'explore.stop': return ['explore', `Stop at ${d.poi_name ?? d.poi_id ?? '?'}`];
      case 'error': return ['error', `Error${d.where ? ` in ${d.where}` : ''}: ${d.message ?? ''}`];
      case 'app.launch': return ['app', `App launched${d.unclean_previous ? ' (previous session ended uncleanly)' : ''}`];
      case 'app.foreground': return ['app', 'App in foreground'];
      case 'app.background': return ['app', `App in background${num(d.seconds_active) ? ` after ${duration(d.seconds_active)} active` : ''}`];
      case 'app.terminate': return ['app', 'App closed'];
      case 'staff.unlock': return ['app', 'Staff mode unlocked'];
      case 'staff.exit': return ['app', 'Staff mode left'];
      case 'map.loaded': return ['app', `Map loaded: ${d.name ?? d.slug ?? 'bundled map'}${d.version != null ? ` v${d.version}` : ''}${d.source ? ` (${d.source})` : ''}`];
      case 'map.download': return ['app', `Map download ${d.slug ?? ''}${d.ok === false ? ` failed${d.error ? `: ${d.error}` : ''}` : ' done'}`.replace('  ', ' ')];
      case 'author.scan': return ['app', `Scan ${d.phase ?? ''}`.trim()];
      case 'author.publish': return ['app', `Publish ${d.phase ?? ''}${d.slug ? ` ${d.slug}` : ''}${d.ok === false ? ' failed' : ''}`.replace(/\s+/g, ' ').trim()];
      case 'field.result': return ['other', `Field result ${d.kind ?? ''}`.trim()];
      case 'beacon': return ['other', `Beacon ${d.on ? 'on' : 'off'}`];
      case 'settings.changed': return ['other', `Setting ${d.key ?? '?'}: ${JSON.stringify(d.old)} → ${JSON.stringify(d.new)}`];
      case 'diag': return ['other', `Diag: ${d.line ?? ''}`];
      default: return ['other', String(e.type ?? 'event')];
    }
  }

  function timeline(events) {
    const names = new Map();
    return sortEvents(events)
      .filter(e => e.type !== 'pose')
      .map(e => {
        const d = dat(e);
        if (e.type === 'nav.request' && d.to_id != null && d.to_name != null) names.set(d.to_id, d.to_name);
        const [kind, text] = describe(e, names);
        return { t: e.t, seq: e.seq, kind, text };
      });
  }

  function cell(v) {
    const s = v == null ? '' : String(v);
    return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  }

  function toCSV(events) {
    const lines = ['session_id,seq,t,type,data'];
    for (const e of sortEvents(events)) {
      lines.push([e.session_id, e.seq, e.t, e.type, JSON.stringify(e.data ?? null)].map(cell).join(','));
    }
    return lines.join('\r\n');
  }

  function summaryCSV(rows) {
    rows = rows || [];
    const cols = [];
    for (const r of rows) for (const k of Object.keys(r)) if (!cols.includes(k)) cols.push(k);
    if (!cols.length) cols.push('id');
    const lines = [cols.map(cell).join(',')];
    for (const r of rows) {
      lines.push(cols.map(c => cell(r[c] !== null && typeof r[c] === 'object' ? JSON.stringify(r[c]) : r[c])).join(','));
    }
    return lines.join('\r\n');
  }

  // Which app logged a session; rows from before the app column count as aiseebin.
  const APP_NAMES = { aiseebin: 'AISEE-BIN', 'nus-open-house': 'NUS Computing Tour' };
  const appId = a => a || 'aiseebin';
  const appName = a => APP_NAMES[appId(a)] || appId(a);

  const api = { appId, appName, sortEvents, pathSegments, fixMarkers, timeline, toCSV, summaryCSV, duration };
  root.Sessions = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
