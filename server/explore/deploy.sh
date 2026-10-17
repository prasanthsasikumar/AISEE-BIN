#!/bin/sh
# Deploys the Explore proxy to the FlowsXR VPS. The env file (/etc/aiseebin-explore.env)
# is created once by hand on the VPS and never leaves it; see README.md.
set -e
HOST=root@104.168.48.121
cd "$(dirname "$0")"
rsync -a --delete --exclude node_modules --exclude '*.test.mjs' ./ "$HOST:/opt/aiseebin-explore/"
ssh "$HOST" 'set -e
  cd /opt/aiseebin-explore
  docker build -q -t aiseebin-explore .
  docker rm -f aiseebin-explore >/dev/null 2>&1 || true
  mkdir -p /var/lib/aiseebin-explore
  docker run -d --name aiseebin-explore --restart unless-stopped \
    -p 127.0.0.1:8790:8787 -v /var/lib/aiseebin-explore:/data \
    --env-file /etc/aiseebin-explore.env aiseebin-explore >/dev/null
  sleep 2; curl -s http://127.0.0.1:8790/explore/health; echo'
