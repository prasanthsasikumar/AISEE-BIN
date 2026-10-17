import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { RateLimiter, buildAskContent, buildAskSystemPrompt, pruneLogs, logPath, sanitizePlan } from './lib.mjs';

test('rate limiter allows 60 per install per hour, then refuses', () => {
  let now = 0;
  const rl = new RateLimiter({ perInstallPerHour: 60, perDay: 2000, now: () => now });
  for (let i = 0; i < 60; i++) assert.equal(rl.take('a'), true);
  assert.equal(rl.take('a'), false);
  assert.equal(rl.take('b'), true, 'another install is unaffected');
  now += 3600_001;
  assert.equal(rl.take('a'), true, 'resets after an hour');
});

test('rate limiter refuses everyone after the daily cap', () => {
  let now = 0;
  const rl = new RateLimiter({ perInstallPerHour: 60, perDay: 5, now: () => now });
  for (let i = 0; i < 5; i++) assert.equal(rl.take(`i${i}`), true);
  assert.equal(rl.take('fresh'), false);
  now += 86_400_001;
  assert.equal(rl.take('fresh'), true);
});

test('ask content has an image block only when given', () => {
  const withImage = buildAskContent({ question: 'What is this?', imageJPEGBase64: 'AAAA', places: [], history: [] });
  assert.equal(withImage[0].type, 'image');
  assert.equal(withImage[0].source.media_type, 'image/jpeg');
  const without = buildAskContent({ question: 'What is this?', places: [], history: [] });
  assert.equal(without.length, 1);
  assert.equal(without[0].type, 'text');
});

test('ask content lists places nearest first, marks the one in view, keeps 3 history pairs', () => {
  const content = buildAskContent({
    question: 'How old is it?',
    places: [
      { id: 'far', name: 'Olive grove', distance: 12, inView: false },
      { id: 'near', name: 'Baobab', about: 'Stores water', distance: 3, inView: true },
    ],
    venueInfo: 'Opens 9am',
    history: [1, 2, 3, 4].map(n => ({ q: `q${n}`, a: `a${n}` })),
  });
  const text = content.at(-1).text;
  assert.ok(text.indexOf('Baobab') < text.indexOf('Olive grove'));
  assert.match(text, /Baobab.*in front of the camera/);
  assert.match(text, /Stores water/);
  assert.match(text, /Opens 9am/);
  assert.ok(!text.includes('q1') && text.includes('q2') && text.includes('q4'));
  assert.ok(text.trim().endsWith('How old is it?'));
});

test('system prompt carries the grounding rules', () => {
  const s = buildAskSystemPrompt();
  assert.match(s, /Flower Dome/);
  assert.match(s, /never invent/i);
  assert.match(s, /2.?3 short sentences/i);
});

test('pruneLogs deletes files older than 30 days and keeps newer ones', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'explore-'));
  const now = new Date('2026-10-17T12:00:00Z');
  const old = logPath(dir, new Date('2026-09-16T00:00:00Z'));
  const recent = logPath(dir, new Date('2026-09-18T00:00:00Z'));
  fs.writeFileSync(old, '{}\n'); fs.writeFileSync(recent, '{}\n');
  pruneLogs(dir, now, 30);
  assert.equal(fs.existsSync(old), false);
  assert.equal(fs.existsSync(recent), true);
  assert.match(path.basename(recent), /^log-2026-09-18\.jsonl$/);
});

test('sanitizePlan keeps only known exhibit ids and a sane minute count', () => {
  const plan = sanitizePlan({ minutes: 20, interests: ['orchids'], mustSee: ['p1', 'nope'] }, [{ id: 'p1' }]);
  assert.deepEqual(plan, { minutes: 20, interests: ['orchids'], mustSee: ['p1'] });
  assert.equal(sanitizePlan({ minutes: -4, interests: [], mustSee: [] }, []).minutes, 20);
  assert.equal(sanitizePlan({ minutes: 600, interests: [], mustSee: [] }, []).minutes, 180);
});
