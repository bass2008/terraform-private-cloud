#!/bin/bash
set -euo pipefail

###############################################################################
# Caddy reverse proxy setup — HTTPS for Headscale + Authelia
# Idempotent. Run on the target VM via SSH.
#
# Required env vars:
#   DOMAIN — e.g. sergey-vpn.duckdns.org
###############################################################################

DOMAIN="${DOMAIN:?Set DOMAIN before running}"

echo "=== Installing Caddy ==="

sudo apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl > /dev/null

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true

echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

sudo apt-get update -qq > /dev/null
sudo apt-get install -y -qq caddy > /dev/null

echo "=== Configuring Caddy ==="

sudo tee /etc/caddy/Caddyfile > /dev/null <<EOF
# Headscale — main VPN coordination server + embedded DERP
${DOMAIN} {
    reverse_proxy localhost:8080
}

# Authelia — OIDC identity provider
https://${DOMAIN}:9443 {
    reverse_proxy localhost:9091
}
EOF

echo "=== Starting Caddy ==="

sudo systemctl enable caddy > /dev/null 2>&1
sudo systemctl restart caddy

sleep 5

if sudo systemctl is-active --quiet caddy; then
  echo "=== Caddy is running ==="
  echo "Headscale: https://${DOMAIN}"
  echo "Authelia:  https://${DOMAIN}:9443"
else
  echo "ERROR: Caddy failed to start"
  sudo journalctl -u caddy --no-pager -n 20
  exit 1
fi
