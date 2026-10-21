// Pure helpers for the Explore proxy: prompts, limits, logs. server.mjs wires them to HTTP.
import fs from 'node:fs';
import path from 'node:path';

const HOUR = 3_600_000;
const DAY = 86_400_000;

/** Per-install hourly cap plus one daily cap across everyone. Fixed windows, in memory. */
export class RateLimiter {
  constructor({ perInstallPerHour, perDay, now = Date.now }) {
    this.perInstallPerHour = perInstallPerHour;
    this.perDay = perDay;
    this.now = now;
    this.installs = new Map(); // id -> { start, count }
    this.day = { start: now(), count: 0 };
  }

  take(installId) {
    const t = this.now();
    if (t - this.day.start > DAY) this.day = { start: t, count: 0 };
    if (this.day.count >= this.perDay) return false;
    let w = this.installs.get(installId);
    if (!w || t - w.start > HOUR) { w = { start: t, count: 0 }; this.installs.set(installId, w); }
    if (w.count >= this.perInstallPerHour) return false;
    w.count += 1;
    this.day.count += 1;
    return true;
  }
}

export function buildAskSystemPrompt() {
  return [
    'You are a friendly guide in the Flower Dome at Gardens by the Bay, Singapore, talking to a visitor',
    'who is walking around with a phone. They point the camera at something and ask a question out loud.',
    'Your answer is read aloud, so reply in 2-3 short sentences of plain spoken English: no lists, no',
    'markdown, no emoji.',
    '',
    'Facts about the Flower Dome, its gardens and exhibits come only from the places and venue information',
    'given with the question. You may describe and identify what is clearly visible in the photo from',
    'general knowledge, but say so plainly when you are not sure ("it looks like..."). Never invent names,',
    'ages, numbers or dates. If you do not know, say so briefly and suggest something they can look at.',
    'If the question has nothing to do with the visit, or is unsafe, answer with one polite line that',
    'steers back to the garden.',
  ].join('\n');
}

/** Message content for one question: the photo (if any) first, then the context and the question. */
export function buildAskContent({ question, imageJPEGBase64, places = [], venueInfo, history = [] }) {
  const lines = [];
  const nearby = [...places].sort((a, b) => a.distance - b.distance);
  if (nearby.length) {
    lines.push('Places near the visitor, nearest first:');
    for (const p of nearby) {
      const facts = [p.details, p.about].filter(Boolean).join(' ');
      const where = `${Math.round(p.distance)} m away${p.inView ? ', in front of the camera' : ''}`;
      lines.push(`- ${p.name} (${where})${facts ? `: ${facts}` : ''}`);
    }
  } else {
    lines.push('The visitor\'s exact position is not known right now.');
  }
  if (venueInfo) lines.push('', `About the venue: ${venueInfo}`);
  const recent = history.slice(-3);
  if (recent.length) {
    lines.push('', 'Earlier in this visit:');
    for (const h of recent) lines.push(`Visitor: ${h.q}`, `Guide: ${h.a}`);
  }
  lines.push('', `The visitor asks: ${question}`);

  const content = [];
  if (imageJPEGBase64) {
    content.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: imageJPEGBase64 } });
  }
  content.push({ type: 'text', text: lines.join('\n') });
  return content;
}

export const PLAN_SCHEMA = {
  type: 'object',
  properties: {
    minutes: { type: 'integer', description: 'How many minutes the visitor has' },
    interests: { type: 'array', items: { type: 'string' }, description: 'Things they said they like' },
    mustSee: { type: 'array', items: { type: 'string' }, description: 'Ids of exhibits they asked for by name' },
  },
  required: ['minutes', 'interests', 'mustSee'],
  additionalProperties: false,
};

export function buildPlanPrompt(utterance, exhibits) {
  const list = exhibits.map(e => `- ${e.id}: ${e.name}${e.tags?.length ? ` (${e.tags.join(', ')})` : ''}`).join('\n');
  return `A visitor at the Flower Dome entrance said: "${utterance}"\n\nExhibits:\n${list}\n\n` +
    'Return how many minutes they have (20 if they did not say), what they said they like, and the ids of any ' +
    'exhibits they asked for by name.';
}

/** Clamps the model's plan to what the app can use. */
export function sanitizePlan(plan, exhibits) {
  const ids = new Set(exhibits.map(e => e.id));
  let minutes = Number(plan?.minutes);
  if (!Number.isFinite(minutes) || minutes <= 0) minutes = 20;
  minutes = Math.min(180, Math.round(minutes));
  const interests = (plan?.interests ?? []).filter(s => typeof s === 'string' && s.trim()).slice(0, 8);
  const mustSee = (plan?.mustSee ?? []).filter(id => ids.has(id));
  return { minutes, interests, mustSee };
}

export function logPath(dir, date) {
  return path.join(dir, `log-${date.toISOString().slice(0, 10)}.jsonl`);
}

export function appendLog(dir, record, now = new Date()) {
  fs.mkdirSync(dir, { recursive: true });
  fs.appendFileSync(logPath(dir, now), JSON.stringify({ at: now.toISOString(), ...record }) + '\n');
}

/** Deletes daily log files older than `days`. */
export function pruneLogs(dir, now = new Date(), days = 30) {
  if (!fs.existsSync(dir)) return;
  const cutoff = now.getTime() - days * DAY;
  for (const name of fs.readdirSync(dir)) {
    const m = /^log-(\d{4}-\d{2}-\d{2})\.jsonl$/.exec(name);
    if (m && Date.parse(`${m[1]}T00:00:00Z`) < cutoff) fs.unlinkSync(path.join(dir, name));
  }
}

/**
 * Streams answer text from Claude's events to the HTTP response. The 200 goes out
 * with the first words, so an upstream failure before then throws and the caller
 * can answer 502; a failure after that keeps what was already sent.
 */
export async function pipeAnswer(events, res) {
  let answer = '';
  try {
    for await (const event of events) {
      if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
        if (!res.headersSent) {
          res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
        }
        answer += event.delta.text;
        res.write(event.delta.text);
      }
    }
  } catch (err) {
    if (!answer) throw err;
    console.error('ask stream broke after', answer.length, 'chars:', err?.message);
  }
  return answer;
}
