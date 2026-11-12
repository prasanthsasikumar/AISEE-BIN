// node --test web/tidy.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const T = require('./tidy.js');

const poi = (id, x, z, category = 'junction', extra = {}) => ({ id, name: id, x, z, category, aliases: [], ...extra });
const chain = pois => ({ name: 't', pois, edges: pois.slice(1).map((p, i) => ({ from: pois[i].id, to: p.id })) });
const links = g => new Set(g.edges.map(e => [e.from, e.to].sort().join('~')));

test('the AHLab walk as published becomes the hand-cleaned graph', () => {
  const d = 'destination';
  const walked = chain([
    poi('praveen', -0.2, 0.6, d), poi('wp-1', -1.2, 0.1), poi('wp-2', 0.5, -1.7),
    poi('chill-room', 5.6, -0.7, d), poi('think-tank', 3.4, -1.4, d), poi('wp-3', -4.5, -3.6),
    poi('island-table', -7.7, -5.9, d), poi('wp-4', -13.1, -5.7), poi('printer', -13.1, -9.3, d),
    poi('door', -11.0, -10.4, d), poi('wp-5', -14.2, -12.2), poi('gpu-machine', -14.0, -14.3, d),
    poi('wp-6', -16.3, -7.5), poi('taka-ghost', -15.9, -6.2, d), poi('wp-7', -15.1, -10.6),
    poi('wp-8', -16.8, -12.9), poi('sankha', -16.4, -14.2, d),
  ]);
  const r = T.tidy(walked);
  assert.deepEqual(links(r.graph), new Set([
    'praveen~wp-1', 'wp-1~wp-2', 'think-tank~wp-2', 'chill-room~think-tank',
    'wp-2~wp-3', 'island-table~wp-3', 'island-table~wp-4', 'printer~wp-4', 'door~printer',
    'door~wp-5', 'gpu-machine~wp-5', 'wp-5~wp-6', 'wp-5~wp-8', 'taka-ghost~wp-6', 'sankha~wp-8',
  ]));
  assert.equal(r.mergedWaypoints, 1);
  assert.ok(!r.graph.pois.some(p => p.id === 'wp-7'));
  const merged = r.graph.pois.find(p => p.id === 'wp-5');
  assert.ok(Math.abs(merged.x + 14.65) < 0.01 && Math.abs(merged.z + 11.4) < 0.01);
  assert.equal(walked.pois.length, 17, 'the input graph is not modified');
});

test('a clean corridor is left alone, and the same object comes back', () => {
  const g = chain([poi('a', 0, 0, 'destination'), poi('w1', 5, 0), poi('w2', 5, 5), poi('b', 10, 5, 'destination')]);
  const r = T.tidy(g);
  assert.equal(r.changed, false);
  assert.equal(r.graph, g);
});

test('tidying twice changes nothing more', () => {
  const once = T.tidy(chain([poi('a', 0, 0, 'destination'), poi('w1', 6, 0), poi('b', 3, 0.4, 'destination'), poi('w2', -3, 0)])).graph;
  assert.equal(T.tidy(once).changed, false);
});

test('places are never merged, and nothing joins across floors', () => {
  assert.equal(T.tidy(chain([poi('a', 0, 0, 'destination'), poi('b', 1, 0, 'exhibit'), poi('c', 8, 0, 'destination')])).changed, false);
  const floors = { name: 't', pois: [poi('a', 0, 0, 'junction', { y: 0 }), poi('b', 10, 0, 'junction', { y: 0 }), poi('up', 5, 0.2, 'junction', { y: 4 }), poi('up2', 5, 9, 'junction', { y: 4 })],
                   edges: [{ from: 'a', to: 'b' }, { from: 'up', to: 'up2' }] };
  assert.equal(T.tidy(floors).changed, false);
});

test('other fields of the graph, points and links are carried over', () => {
  const g = chain([poi('a', 0, 0, 'destination', { details: 'hello' }), poi('w1', 6, 0), poi('b', 3, 0.3, 'exhibit')]);
  g.immersalAlignment = { mapIDs: [1] }; g.tourStart = 'a'; g.edges[0].kind = 'ramp';
  const r = T.tidy(g);
  assert.ok(r.changed);
  assert.deepEqual(r.graph.immersalAlignment, { mapIDs: [1] });
  assert.equal(r.graph.tourStart, 'a');
  assert.equal(r.graph.pois.find(p => p.id === 'a').details, 'hello');
  assert.ok(r.graph.edges.every(e => e.from !== e.to));
  assert.ok(r.graph.edges.filter(e => e.kind === 'ramp').length >= 1);
});

test('summary reads naturally', () => {
  assert.equal(T.summary({ mergedWaypoints: 1, reroutedLinks: 4 }), '1 waypoint merged, 4 links re-routed');
  assert.equal(T.summary({ mergedWaypoints: 2, reroutedLinks: 0 }), '2 waypoints merged');
});
