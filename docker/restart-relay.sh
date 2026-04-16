#!/bin/bash
set -euo pipefail

###############################################################################
# Restart DERP relay — fixes hung connections
# Run on the VM: bash ~/docker/restart-relay.sh
###############################################################################

cd "$(dirname "$0")"

echo "Restarting headscale (DERP relay)..."
docker compose restart headscale

echo "Restarting exit nodes..."
docker compose restart yc-node us-node

sleep 10

echo "Status:"
docker compose exec -T headscale headscale nodes list
