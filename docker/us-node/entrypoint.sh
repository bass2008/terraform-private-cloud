#!/bin/sh
set -e

# Wait for us-corp to be reachable
echo "Waiting for us-corp..."
while ! ping -c1 -W1 us-corp >/dev/null 2>&1; do
  sleep 1
done

# Set default route through us-corp
CORP_IP=$(getent hosts us-corp | awk '{print $1}')
echo "Setting default route via us-corp ($CORP_IP)"
ip route del default 2>/dev/null || true
ip route add default via "$CORP_IP"

# Start tailscaled in background
tailscaled --state=/var/lib/tailscale/tailscaled.state &
sleep 3

# Register with Headscale using TS_EXTRA_ARGS
echo "Connecting to Headscale..."
tailscale up $TS_EXTRA_ARGS

# Keep container running
wait
