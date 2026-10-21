// Explore proxy: holds the Claude key so the app never does. Behind Caddy at
// https://aiseebin.flowsxr.com/explore/{ask,plan}. Config comes from the env file.
import http from 'node:http';
import Anthropic from '@anthropic-ai/sdk';
import {
  RateLimiter, buildAskSystemPrompt, buildAskContent, buildPlanPrompt, PLAN_SCHEMA,
  sanitizePlan, appendLog, pruneLogs, pipeAnswer,
} from './lib.mjs';

const env = process.env;
const PORT = Number(env.PORT ?? 8787);
const MODEL = env.EXPLORE_MODEL ?? 'claude-opus-5-5';
const EFFORT = env.EXPLORE_EFFORT ?? 'low';
const LOG_DIR = env.EXPLORE_LOG_DIR ?? '/data';
const MAX_BODY = 1.5 * 1024 * 1024;
const enabled = () => env.EXPLORE_ENABLED !== '0';

const client = new Anthropic(); // ANTHROPIC_API_KEY from the env file
const limiter = new RateLimiter({ perInstallPerHour: 60, perDay: 2000 });
// Server-side fallback on a policy decline, routed by category.
const FALLBACK = { betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' };

pruneLogs(LOG_DIR);
setInterval(() => pruneLogs(LOG_DIR), 86_400_000).unref();

function readJSON(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', c => {
      size += c.length;
      if (size > MAX_BODY) { reject(Object.assign(new Error('too large'), { status: 413 })); req.destroy(); }
      else chunks.push(c);
    });
    req.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
      catch { reject(Object.assign(new Error('bad json'), { status: 400 })); }
    });
    req.on('error', reject);
  });
}

function send(res, status, body, type = 'application/json') {
  res.writeHead(status, { 'content-type': type });
  res.end(typeof body === 'string' ? body : JSON.stringify(body));
}

async function ask(req, res, installId) {
  const body = await readJSON(req);
  if (typeof body.question !== 'string' || !body.question.trim()) return send(res, 400, { error: 'question' });
  const started = Date.now();
  let answer = '';
  let status = 200;
  try {
    const stream = client.beta.messages.stream({
      model: MODEL,
      max_tokens: 400,
      output_config: { effort: EFFORT },
      system: buildAskSystemPrompt(),
      messages: [{ role: 'user', content: buildAskContent(body) }],
      ...FALLBACK,
    });
    answer = await pipeAnswer(stream, res);
    const final = answer ? null : await stream.finalMessage();
    if (!answer && final?.stop_reason === 'refusal') {
      answer = "Sorry, I can't help with that one. Ask me about the plants around you.";
      send(res, 200, answer, 'text/plain; charset=utf-8');
    } else if (!answer) {
      status = 502;
      send(res, 502, { error: 'empty' });
    }
  } catch (err) {
    console.error('ask failed', err?.status, err?.message);
    status = 502;
    if (!res.headersSent) send(res, 502, { error: 'upstream' });
  }
  if (!res.writableEnded) res.end();
  appendLog(LOG_DIR, {
    route: 'ask', status, installId, mapSlug: body.mapSlug, question: body.question, answer,
    places: (body.places ?? []).map(p => p.id), image: Boolean(body.imageJPEGBase64),
    totalMS: Date.now() - started,
  });
}

async function plan(req, res, installId) {
  const body = await readJSON(req);
  const exhibits = Array.isArray(body.exhibits) ? body.exhibits : [];
  if (typeof body.utterance !== 'string') return send(res, 400, { error: 'utterance' });
  const started = Date.now();
  const msg = await client.beta.messages.create({
    model: MODEL,
    max_tokens: 1000,
    output_config: { effort: EFFORT, format: { type: 'json_schema', schema: PLAN_SCHEMA } },
    messages: [{ role: 'user', content: buildPlanPrompt(body.utterance, exhibits) }],
    ...FALLBACK,
  });
  const text = msg.content.filter(b => b.type === 'text').map(b => b.text).join('');
  let parsed = {};
  try { parsed = JSON.parse(text); } catch { /* sanitizePlan falls back to 20 minutes */ }
  const result = sanitizePlan(parsed, exhibits);
  send(res, 200, result);
  appendLog(LOG_DIR, { route: 'plan', installId, utterance: body.utterance, result, totalMS: Date.now() - started });
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/explore/health') return send(res, 200, { ok: true, enabled: enabled() });
    if (req.method !== 'POST') return send(res, 405, { error: 'method' });
    if (!env.EXPLORE_TOKEN || req.headers['x-explore-token'] !== env.EXPLORE_TOKEN) return send(res, 401, { error: 'token' });
    if (!enabled()) return send(res, 503, { error: 'disabled' });
    const installId = String(req.headers['x-install-id'] ?? 'unknown').slice(0, 64);
    if (!limiter.take(installId)) return send(res, 429, { error: 'limit' });
    if (req.url === '/explore/ask') return await ask(req, res, installId);
    if (req.url === '/explore/plan') return await plan(req, res, installId);
    send(res, 404, { error: 'route' });
  } catch (err) {
    console.error(err);
    if (!res.headersSent) send(res, err.status ?? 502, { error: err.message });
    else res.end();
  }
});

server.listen(PORT, () => console.log(`explore proxy on :${PORT}, model ${MODEL}, effort ${EFFORT}`));
