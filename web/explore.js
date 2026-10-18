// Explore-mode fields for the map editor: tour start/end, venue info, and per-place
// minutes, highlight, tags, about and photo. All optional: an empty input removes
// the key, so maps without Explore content stay exactly as they were.
//
// Plain script for the browser (exposes `ExploreFields`) and a CommonJS module for
// the node tests. No DOM in here: app.js does the wiring.
(function (root) {
  'use strict';

  const TEXT = ['about', 'photo', 'venueInfo', 'tourStart', 'tourEnd'];

  function applyField(obj, key, raw) {
    const v = String(raw ?? '').trim();
    if (key === 'minutes') {
      const n = parseFloat(v);
      if (Number.isFinite(n) && n > 0) obj.minutes = n; else delete obj.minutes;
    } else if (key === 'highlight') {
      const n = parseInt(v, 10);
      if (v !== '' && [0, 1, 3].includes(n)) obj.highlight = n; else delete obj.highlight;
    } else if (key === 'tags') {
      const tags = v.split(',').map(s => s.trim()).filter(Boolean);
      if (tags.length) obj.tags = tags; else delete obj.tags;
    } else if (TEXT.includes(key)) {
      if (v) obj[key] = v; else delete obj[key];
    }
  }

  function fieldValue(obj, key) {
    const v = obj?.[key];
    if (v === undefined || v === null) return '';
    if (key === 'tags') return v.join(', ');
    return String(v);
  }

  const api = { applyField, fieldValue };
  root.ExploreFields = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
