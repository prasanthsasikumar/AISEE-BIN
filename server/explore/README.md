# Explore proxy

Holds the Claude API key for the app's Explore mode. Runs in Docker on the FlowsXR VPS, behind Caddy:

- `POST https://aiseebin.flowsxr.com/explore/ask` streams a short spoken-style answer (text/plain).
- `POST https://aiseebin.flowsxr.com/explore/plan` turns "I've got 20 minutes, I love orchids" into
  `{ minutes, interests, mustSee }`.
- `GET /explore/health`.

Both POST routes need `X-Explore-Token` (baked into the app via the `EXPLORE_TOKEN` build setting) and an
`X-Install-Id`. Limits: 60 per install per hour, 2,000 per day overall.

## Env file (`/etc/aiseebin-explore.env` on the VPS, chmod 600, never in git)

```
ANTHROPIC_API_KEY=...
EXPLORE_TOKEN=...            # openssl rand -hex 24
EXPLORE_MODEL=claude-opus-5-5
EXPLORE_EFFORT=low
EXPLORE_ENABLED=1            # 0 switches both routes off (503)
```

After editing it: `docker restart aiseebin-explore` (or re-run `deploy.sh`).

## Logs

`/var/lib/aiseebin-explore/log-YYYY-MM-DD.jsonl` on the VPS: question, answer, nearby place ids and timing.
No images. Files older than 30 days are deleted automatically.

## Develop

`npm install && node --test`; `./deploy.sh` to ship.
