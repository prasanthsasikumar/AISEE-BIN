// node --test web/explore.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const { applyField, fieldValue } = require('./explore.js');

test('minutes: a positive number is kept, anything else removes the key', () => {
  const p = {};
  applyField(p, 'minutes', '4.5'); assert.equal(p.minutes, 4.5);
  applyField(p, 'minutes', ''); assert.ok(!('minutes' in p));
  applyField(p, 'minutes', '-2'); assert.ok(!('minutes' in p));
});

test('highlight: Good (empty) removes the key, 0 is kept', () => {
  const p = {};
  applyField(p, 'highlight', '0'); assert.equal(p.highlight, 0);
  applyField(p, 'highlight', '1'); assert.equal(p.highlight, 1);
  applyField(p, 'highlight', ''); assert.ok(!('highlight' in p));
});

test('tags: comma list, trimmed, empty removes the key', () => {
  const p = {};
  applyField(p, 'tags', ' orchids, desert ,,'); assert.deepEqual(p.tags, ['orchids', 'desert']);
  applyField(p, 'tags', ' '); assert.ok(!('tags' in p));
});

test('text fields: trimmed, empty removes the key', () => {
  const g = {};
  applyField(g, 'venueInfo', '  Opens 9am '); assert.equal(g.venueInfo, 'Opens 9am');
  applyField(g, 'tourStart', ''); assert.ok(!('tourStart' in g));
  applyField(g, 'about', ''); assert.ok(!('about' in g));
});

test('fieldValue renders what the inputs show', () => {
  assert.equal(fieldValue({ tags: ['a', 'b'] }, 'tags'), 'a, b');
  assert.equal(fieldValue({}, 'highlight'), '');
  assert.equal(fieldValue({ highlight: 0 }, 'highlight'), '0');
  assert.equal(fieldValue({ minutes: 3 }, 'minutes'), '3');
});
