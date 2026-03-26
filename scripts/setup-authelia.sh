#!/bin/bash
set -euo pipefail

###############################################################################
# Authelia OIDC provider setup — login/password auth for Headscale
# Idempotent. Run on the target VM via SSH.
#
# Required env vars:
#   DOMAIN             — e.g. sergey-vpn.duckdns.org
#   AUTHELIA_PASSWORD  — password for all users
###############################################################################

DOMAIN="${DOMAIN:?Set DOMAIN before running}"
USER_PASSWORD="${AUTHELIA_PASSWORD:?Set AUTHELIA_PASSWORD before running}"

SECRETS_DIR="/etc/authelia/secrets"
DATA_DIR="/var/lib/authelia"

AUTHELIA_VERSION="4.39.16"

echo "=== Installing Authelia v${AUTHELIA_VERSION} ==="

if ! command -v authelia &> /dev/null || ! authelia --version 2>/dev/null | grep -q "$AUTHELIA_VERSION"; then
  TARBALL="/tmp/authelia-v${AUTHELIA_VERSION}-linux-amd64.tar.gz"
  if [ ! -f "$TARBALL" ]; then
    curl -fsSL -o "$TARBALL" \
      "https://github.com/authelia/authelia/releases/download/v${AUTHELIA_VERSION}/authelia-v${AUTHELIA_VERSION}-linux-amd64.tar.gz"
  fi
  sudo tar xzf "$TARBALL" -C /usr/local/bin/ authelia
  sudo chmod +x /usr/local/bin/authelia
fi

sudo mkdir -p /etc/authelia
echo "Authelia version: $(authelia --version 2>/dev/null || echo 'unknown')"

echo "=== Generating secrets (idempotent) ==="

sudo mkdir -p "$SECRETS_DIR" "$DATA_DIR"

for SECRET_NAME in jwt storage-key session oidc-hmac; do
  if [ ! -f "$SECRETS_DIR/$SECRET_NAME" ]; then
    openssl rand -hex 32 | sudo tee "$SECRETS_DIR/$SECRET_NAME" > /dev/null
    echo "  Generated $SECRET_NAME"
  fi
done

if [ ! -f "$SECRETS_DIR/oidc-rsa-key.pem" ]; then
  openssl genrsa 4096 2>/dev/null | sudo tee "$SECRETS_DIR/oidc-rsa-key.pem" > /dev/null
  echo "  Generated RSA key"
fi

if [ ! -f "$SECRETS_DIR/oidc-client-secret" ]; then
  openssl rand -hex 16 | sudo tee "$SECRETS_DIR/oidc-client-secret" > /dev/null
  echo "  Generated OIDC client secret"
fi

echo "=== Hashing passwords ==="

PASSWORD_HASH=$(authelia crypto hash generate argon2 --password "$USER_PASSWORD" 2>&1 | grep -oP '\$argon2[^\s]+')
OIDC_CLIENT_SECRET_PLAIN=$(sudo cat "$SECRETS_DIR/oidc-client-secret")
CLIENT_SECRET_HASH=$(authelia crypto hash generate pbkdf2 --variant sha512 --password "$OIDC_CLIENT_SECRET_PLAIN" 2>&1 | grep -oP '\$pbkdf2[^\s]+')

echo "=== Writing users database ==="

sudo tee /etc/authelia/users_database.yml > /dev/null <<USERSEOF
users:
  sergey:
    displayname: "Sergey"
    password: "${PASSWORD_HASH}"
    email: sergey@${DOMAIN}
  victoria:
    displayname: "Victoria"
    password: "${PASSWORD_HASH}"
    email: victoria@${DOMAIN}
USERSEOF

echo "=== Writing configuration ==="

# Use Python to safely embed RSA key in YAML
sudo DOMAIN="$DOMAIN" CLIENT_SECRET_HASH="$CLIENT_SECRET_HASH" python3 <<'PYEOF'
import os

domain = os.environ['DOMAIN']
client_secret_hash = os.environ['CLIENT_SECRET_HASH']
secrets_dir = '/etc/authelia/secrets'

jwt_secret = open(f'{secrets_dir}/jwt').read().strip()
storage_key = open(f'{secrets_dir}/storage-key').read().strip()
session_secret = open(f'{secrets_dir}/session').read().strip()
oidc_hmac = open(f'{secrets_dir}/oidc-hmac').read().strip()
rsa_key = open(f'{secrets_dir}/oidc-rsa-key.pem').read().rstrip()
rsa_key_indented = '\n'.join('          ' + line for line in rsa_key.split('\n'))

config = f"""---
theme: dark

server:
  address: 'tcp://127.0.0.1:9091/'

log:
  level: info

identity_validation:
  reset_password:
    jwt_secret: '{jwt_secret}'

authentication_backend:
  file:
    path: /etc/authelia/users_database.yml

session:
  secret: '{session_secret}'
  cookies:
    - domain: '{domain}'
      authelia_url: 'https://{domain}:9443'

storage:
  encryption_key: '{storage_key}'
  local:
    path: /var/lib/authelia/db.sqlite3

notifier:
  filesystem:
    filename: /var/lib/authelia/notification.txt

access_control:
  default_policy: one_factor

identity_providers:
  oidc:
    hmac_secret: '{oidc_hmac}'
    jwks:
      - key_id: 'main'
        key: |
{rsa_key_indented}
    clients:
      - client_id: 'headscale'
        client_name: 'Headscale VPN'
        client_secret: '{client_secret_hash}'
        public: false
        authorization_policy: 'one_factor'
        redirect_uris:
          - 'https://{domain}/oidc/callback'
        scopes:
          - 'openid'
          - 'profile'
          - 'email'
        response_types:
          - 'code'
        grant_types:
          - 'authorization_code'
        userinfo_signed_response_alg: 'none'
        token_endpoint_auth_method: 'client_secret_basic'
"""

with open('/etc/authelia/configuration.yml', 'w') as f:
    f.write(config)

print('  Config written to /etc/authelia/configuration.yml')
PYEOF

echo "=== Creating systemd service ==="

sudo tee /etc/systemd/system/authelia.service > /dev/null <<'SVCEOF'
[Unit]
Description=Authelia authentication server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/authelia --config /etc/authelia/configuration.yml
Restart=always
RestartSec=5
WorkingDirectory=/var/lib/authelia

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload

echo "=== Starting Authelia ==="

sudo systemctl enable authelia > /dev/null 2>&1
sudo systemctl restart authelia

sleep 3

if sudo systemctl is-active --quiet authelia; then
  echo "=== Authelia is running ==="
  echo "URL: https://${DOMAIN}:9443"
  echo "OIDC Client Secret (plain): ${OIDC_CLIENT_SECRET_PLAIN}"
else
  echo "ERROR: Authelia failed to start"
  sudo journalctl -u authelia --no-pager -n 30
  exit 1
fi
