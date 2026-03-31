#!/bin/sh
set -e

# Enable NAT for exit node traffic
iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Start containerboot (standard tailscale entrypoint)
exec /usr/local/bin/containerboot
