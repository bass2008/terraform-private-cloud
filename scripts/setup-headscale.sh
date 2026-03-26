#!/bin/bash
set -euo pipefail

###############################################################################
# Headscale setup script — idempotent, no configuration drift
# Run on the target VM via SSH.
#
# Required env vars:
#   DOMAIN — e.g. sergey-vpn.duckdns.org
#
# Optional:
#   HEADSCALE_OIDC=true — enable OIDC auth via Authelia
#     (requires setup-authelia.sh to be run first)
###############################################################################

DOMAIN="${DOMAIN:?Set DOMAIN before running}"
HEADSCALE_PORT="8080"
HEADSCALE_VERSION="0.28.0"
ENABLE_OIDC="${HEADSCALE_OIDC:-false}"

echo "=== Installing Headscale v${HEADSCALE_VERSION} ==="

DEB_FILE="/tmp/headscale_${HEADSCALE_VERSION}_linux_amd64.deb"
if [ ! -f "$DEB_FILE" ]; then
  curl -fsSL -o "$DEB_FILE" \
    "https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION}_linux_amd64.deb"
fi
sudo DEBIAN_FRONTEND=noninteractive dpkg -i --force-confold "$DEB_FILE"

echo "=== Configuring Headscale ==="

# Build OIDC config section
OIDC_CONFIG=""
if [ "$ENABLE_OIDC" = "true" ]; then
  OIDC_SECRET_FILE="/etc/authelia/secrets/oidc-client-secret"
  if [ ! -f "$OIDC_SECRET_FILE" ]; then
    echo "ERROR: OIDC client secret not found at $OIDC_SECRET_FILE"
    echo "Run setup-authelia.sh first."
    exit 1
  fi
  OIDC_CLIENT_SECRET=$(sudo cat "$OIDC_SECRET_FILE")

  OIDC_CONFIG="
oidc:
  only_start_if_oidc_is_available: true
  issuer: https://${DOMAIN}:9443
  client_id: headscale
  client_secret: ${OIDC_CLIENT_SECRET}
  scope:
    - openid
    - profile
    - email
  pkce:
    enabled: true
    method: S256"

  echo "  OIDC enabled (issuer: https://${DOMAIN}:9443)"
fi

# Write config (always overwrite — single source of truth)
sudo mkdir -p /etc/headscale
sudo tee /etc/headscale/config.yaml > /dev/null <<YAML
---
server_url: https://${DOMAIN}
listen_addr: 127.0.0.1:${HEADSCALE_PORT}
metrics_listen_addr: 127.0.0.1:9090

grpc_listen_addr: 127.0.0.1:50443
grpc_allow_insecure: false

noise:
  private_key_path: /var/lib/headscale/noise_private.key

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential

database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite
    write_ahead_log: true

derp:
  server:
    enabled: true
    region_id: 999
    region_code: "yc"
    region_name: "Yandex Cloud"
    private_key_path: /var/lib/headscale/derp_server_private.key
    stun_listen_addr: 0.0.0.0:3478
    automatically_add_embedded_derp_region: true
  urls: []
  paths: []
  auto_update_enabled: false
  update_frequency: 24h

disable_check_updates: false

log:
  format: text
  level: info

policy:
  mode: file
  path: ""

dns:
  magic_dns: true
  base_domain: personal.tail
  nameservers:
    global:
      - 1.1.1.1
      - 8.8.8.8
${OIDC_CONFIG}
YAML

echo "=== Enabling IP forwarding ==="

sudo tee /etc/sysctl.d/99-headscale.conf > /dev/null <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl --system > /dev/null 2>&1

echo "=== Starting Headscale ==="

sudo systemctl enable headscale > /dev/null 2>&1
sudo systemctl restart headscale

sleep 3

if sudo systemctl is-active --quiet headscale; then
  echo "=== Headscale is running ==="
  echo "Server URL: https://${DOMAIN}"
  headscale version
else
  echo "ERROR: Headscale failed to start"
  sudo journalctl -u headscale --no-pager -n 20
  exit 1
fi
