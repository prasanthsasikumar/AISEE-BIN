// node --test web/sessions.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const S = require('./sessions.js');

const T0 = Date.parse('2026-11-07T10:00:00.000Z');
let n = 0;
function ev(type, data = {}, sec = 0, seq = n++) {
  return { session_id: 's1', seq, t: new Date(T0 + sec * 1000).toISOString(), type, data };
}
const pose = (x, z, sec, extra = {}) => ev('pose', { x, z, heading: 0, tracking: 'normal', localized: true, ...extra }, sec);

test('sortEvents orders by seq without mutating input', () => {
  const input = [ev('a', {}, 0, 2), ev('b', {}, 0, 0), ev('c', {}, 0, 1)];
  const out = S.sortEvents(input);
  assert.deepEqual(out.map(e => e.seq), [0, 1, 2]);
  assert.deepEqual(input.map(e => e.seq), [2, 0, 1]);
});

test('pathSegments splits at map.loaded and drops unlocalized poses', () => {
  n = 0;
  const events = [
    ev('map.loaded', { slug: 'a', version: 1 }, 0),
    pose(0, 0, 1), pose(1, 0, 2), pose(9, 9, 3, { localized: false }), pose(2, 0, 4),
    ev('map.loaded', { slug: 'b', version: 2 }, 5),
    pose(5, 5, 6), pose(6, 5, 7),
  ];
  const segs = S.pathSegments(S.sortEvents(events).reverse());
  assert.equal(segs.length, 2);
  assert.deepEqual(segs.map(s => [s.slug, s.version, s.points.length]), [['a', 1, 3], ['b', 2, 2]]);
  assert.ok(!segs[0].points.some(p => p.x === 9));
});

test('pathSegments splits on gaps over 10 s and skips non-finite poses', () => {
  n = 0;
  const segs = S.pathSegments([pose(0, 0, 0), pose(1, 0, 1), pose(NaN, 0, 2), pose(2, 0, 15)]);
  assert.deepEqual(segs.map(s => s.points.length), [2, 1]);
});

test('pathSegments keeps null-slug segments (bundled map)', () => {
  n = 0;
  const segs = S.pathSegments([ev('map.loaded', { slug: null, version: null }), pose(0, 0, 1)]);
  assert.equal(segs.length, 1);
  assert.equal(segs[0].slug, null);
});

test('fixMarkers uses the next localized pose within 2 s', () => {
  n = 0;
  const events = [
    ev('loc.attempt', { ok: true, accepted: true }, 0),
    pose(3, 4, 1),
    ev('loc.attempt', { ok: false }, 20),
    pose(7, 7, 30),
  ];
  const m = S.fixMarkers(events);
  assert.equal(m.length, 1);
  assert.deepEqual([m[0].x, m[0].z, m[0].ok, m[0].accepted], [3, 4, true, true]);
});

test('timeline works without app.launch and never throws on unknown types', () => {
  n = 0;
  const tl = S.timeline([ev('speech.heard', { text: 'take me to the exit' }), ev('weird.type', null), ev('diag', { line: 'x' })]);
  assert.equal(tl.length, 3);
  assert.equal(tl[0].kind, 'heard');
  assert.equal(tl[0].text, 'Heard: “take me to the exit”');
});

test('timeline text for said and arrived', () => {
  n = 0;
  const tl = S.timeline([
    ev('speech.said', { text: 'Turn left' }),
    ev('nav.arrived', { to_id: 'x', to_name: 'Exit', seconds: 190 }),
  ]);
  assert.equal(tl[0].text, 'Said: “Turn left”');
  assert.equal(tl[1].kind, 'nav');
  assert.equal(tl[1].text, 'Arrived at Exit after 3 m 10 s');
});

test('toCSV quotes quotes, commas and newlines', () => {
  n = 0;
  const csv = S.toCSV([ev('speech.heard', { text: 'a "b", c\nd' })]);
  const lines = csv.split('\r\n');
  assert.equal(lines[0], 'session_id,seq,t,type,data');
  assert.ok(csv.includes('"{""text"":""a \\""b\\"", c\\nd""}"'));
});

test('summaryCSV has a header and a row per session', () => {
  const csv = S.summaryCSV([{ id: 's1', started_at: 'x', note: 'a,b' }]);
  assert.ok(csv.startsWith('id,'));
  assert.ok(csv.includes('"a,b"'));
});

test('arrived and cancel take the destination name from the matching nav.request', () => {
  n = 0;
  const tl = S.timeline([
    ev('nav.request', { to_id: 'exit', to_name: 'Exit', path_m: 40 }),
    ev('nav.arrived', { to_id: 'exit', seconds: 190 }),
    ev('nav.request', { to_id: 'cafe', to_name: 'Cafe' }),
    ev('nav.cancel', { to_id: 'cafe', seconds: 5, reason: 'user_stop' }),
    ev('nav.arrived', { to_id: 'toilet', to_name: 'Toilets', seconds: 3 }),
    ev('nav.arrived', { to_id: 'lift', seconds: 3 }),
  ]);
  assert.equal(tl[1].text, 'Arrived at Exit after 3 m 10 s');
  assert.equal(tl[3].text, 'Navigation to Cafe cancelled (user stop) after 5 s');
  assert.equal(tl[4].text, 'Arrived at Toilets after 3 s');
  assert.equal(tl[5].text, 'Arrived at lift after 3 s');
});

test('a session that starts at app.foreground (new session after a long background) keeps its map', () => {
  n = 0;
  // What the apps re-log at seq 1.. of a new session: map.loaded (cache, ms 0), mode.enter, positioning.start.
  const events = [
    ev('app.foreground', {}, 0),
    ev('map.loaded', { slug: 'flower-dome', version: 4, name: 'Flower Dome', source: 'cache', ms: 0 }, 0),
    ev('mode.enter', { mode: 'Navigate' }, 0),
    ev('positioning.start', { source: 'phone', localizer: 'cloud' }, 0),
    pose(0, 0, 1), pose(1, 0, 2), pose(2, 0, 3),
  ];
  const segs = S.pathSegments(events);
  assert.equal(segs.length, 1);
  assert.equal(segs[0].slug, 'flower-dome');
  assert.equal(segs[0].version, 4);
  assert.equal(segs[0].points.length, 3);
  assert.ok(S.timeline(events).some(r => /Flower Dome/.test(r.text ?? JSON.stringify(r))));
});

test('appName treats a missing app as aiseebin and names the NUS app', () => {
  assert.equal(S.appId(undefined), 'aiseebin');
  assert.equal(S.appId(null), 'aiseebin');
  assert.equal(S.appName(null), 'AISEE-BIN');
  assert.equal(S.appName('aiseebin'), 'AISEE-BIN');
  assert.equal(S.appName('nus-open-house'), 'NUS Computing Tour');
  assert.equal(S.appName('other'), 'other');
});
