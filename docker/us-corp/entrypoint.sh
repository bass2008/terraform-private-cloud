#!/bin/sh
set -e

# Start tailscaled in background
tailscaled --state=/var/lib/tailscale/tailscaled.state &
sleep 3

# Enable NAT for traffic from us-node (reapply on every start)
iptables -t nat -C POSTROUTING -o tailscale0 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -o tailscale0 -j MASQUERADE
iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Keep container running
wait
