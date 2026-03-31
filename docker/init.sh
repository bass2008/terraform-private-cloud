#!/bin/bash
set -euo pipefail

###############################################################################
# First-time initialization for docker-compose VPN stack
# Run on the target VM via SSH.
#
# Reads configuration from .env file. Copy .env.example to .env and edit.
# After init, run: docker compose up -d
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "ERROR: .env file not found. Copy .env.example to .env and edit it."
  exit 1
fi

source .env

DOMAIN="${DOMAIN:?Set DOMAIN in .env}"
USERS="${USERS:?Set USERS in .env (JSON array)}"
CORP_LOGIN_SERVER="${CORP_LOGIN_SERVER:?Set CORP_LOGIN_SERVER in .env}"
CORP_EXIT_NODE="${CORP_EXIT_NODE:?Set CORP_EXIT_NODE in .env}"

echo "=== Installing dependencies ==="

if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker ubuntu
fi

if ! command -v authelia &>/dev/null; then
  AUTHELIA_VERSION="4.39.16"
  TARBALL="/tmp/authelia-v${AUTHELIA_VERSION}-linux-amd64.tar.gz"
  if [ ! -f "$TARBALL" ]; then
    curl -fsSL -o "$TARBALL" \
      "https://github.com/authelia/authelia/releases/download/v${AUTHELIA_VERSION}/authelia-v${AUTHELIA_VERSION}-linux-amd64.tar.gz"
  fi
  sudo tar xzf "$TARBALL" -C /usr/local/bin/ authelia
  sudo chmod +x /usr/local/bin/authelia
fi

echo "=== Generating secrets ==="

mkdir -p secrets
for SECRET in jwt storage-key session oidc-hmac; do
  if [ ! -f "secrets/$SECRET" ]; then
    openssl rand -hex 32 > "secrets/$SECRET"
    echo "  Generated $SECRET"
  fi
done

if [ ! -f "secrets/oidc-rsa-key.pem" ]; then
  openssl genrsa 4096 2>/dev/null > "secrets/oidc-rsa-key.pem"
  echo "  Generated RSA key"
fi

if [ ! -f "secrets/oidc-client-secret" ]; then
  openssl rand -hex 16 > "secrets/oidc-client-secret"
  echo "  Generated OIDC client secret"
fi

export OIDC_CLIENT_SECRET=$(cat secrets/oidc-client-secret)

echo "=== Generating Headscale config ==="

export DOMAIN
envsubst < headscale/config.yaml.tpl > headscale/config.yaml
echo "  Written headscale/config.yaml"

echo "=== Generating Authelia config ==="

CLIENT_SECRET_HASH=$(authelia crypto hash generate pbkdf2 --variant sha512 --password "$OIDC_CLIENT_SECRET" 2>&1 | grep -oP '\$pbkdf2[^\s]+')

JWT_SECRET=$(cat secrets/jwt)
STORAGE_KEY=$(cat secrets/storage-key)
SESSION_SECRET=$(cat secrets/session)
OIDC_HMAC=$(cat secrets/oidc-hmac)

python3 <<PYEOF
import os, json

domain = "$DOMAIN"
jwt_secret = "$JWT_SECRET"
storage_key = "$STORAGE_KEY"
session_secret = "$SESSION_SECRET"
oidc_hmac = "$OIDC_HMAC"
client_secret_hash = "$CLIENT_SECRET_HASH"
rsa_key = open("secrets/oidc-rsa-key.pem").read().rstrip()
rsa_key_indented = '\n'.join('          ' + line for line in rsa_key.split('\n'))

config = f"""---
theme: dark

server:
  address: 'tcp://0.0.0.0:9091/'

log:
  level: info

identity_validation:
  reset_password:
    jwt_secret: '{jwt_secret}'

authentication_backend:
  file:
    path: /config/users_database.yml

session:
  secret: '{session_secret}'
  cookies:
    - domain: '{domain}'
      authelia_url: 'https://{domain}:9443'

storage:
  encryption_key: '{storage_key}'
  local:
    path: /data/db.sqlite3

notifier:
  filesystem:
    filename: /data/notification.txt

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

with open('authelia/configuration.yml', 'w') as f:
    f.write(config)
print('  Written authelia/configuration.yml')

# Generate users_database.yml from USERS json
users = json.loads('''$USERS''')
lines = ["users:"]
for u in users:
    pw = os.popen(f"authelia crypto hash generate argon2 --password '{u['password']}' 2>&1 | grep -oP '\\\\\\$argon2[^\\\\s]+'").read().strip()
    lines.append(f"  {u['name']}:")
    lines.append(f"    displayname: \"{u['name'].title()}\"")
    lines.append(f"    password: \"{pw}\"")
    lines.append(f"    email: {u['email']}")

with open('authelia/users_database.yml', 'w') as f:
    f.write('\n'.join(lines) + '\n')
print('  Written authelia/users_database.yml')
PYEOF

echo "=== Enabling IP forwarding ==="

sudo tee /etc/sysctl.d/99-vpn.conf > /dev/null <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl --system > /dev/null 2>&1

echo "=== Making entrypoints executable ==="

chmod +x us-corp/entrypoint.sh us-node/entrypoint.sh yc-node/entrypoint.sh

echo "=== Starting Headscale without OIDC (to generate auth keys) ==="

# Temporarily strip OIDC from config so headscale can start without Authelia
sed '/^oidc:/,$d' headscale/config.yaml > headscale/config.yaml.nooidc
cp headscale/config.yaml headscale/config.yaml.full
cp headscale/config.yaml.nooidc headscale/config.yaml

docker compose up -d headscale
echo "  Waiting for Headscale to be healthy..."
for i in $(seq 1 30); do
  if docker compose exec -T headscale headscale health 2>/dev/null | grep -q "pass"; then
    break
  fi
  sleep 2
done

echo "=== Creating Headscale users ==="

# Create users from USERS json
python3 -c "import json; [print(u['name']) for u in json.loads('''$USERS''')]" | while read USER; do
  docker compose exec -T headscale headscale users create "$USER" 2>/dev/null || true
  echo "  User $USER ready"
done

echo "=== Generating auth keys ==="

FIRST_USER=$(python3 -c "import json; print(json.loads('''$USERS''')[0]['name'])")
USER_ID=$(docker compose exec -T headscale headscale users list -o json 2>/dev/null \
  | python3 -c "
import sys, json
users = json.load(sys.stdin)
for u in users:
    if u.get('name') == '$FIRST_USER':
        print(u['id'])
        break
")

YC_KEY=$(docker compose exec -T headscale headscale preauthkeys create --user "$USER_ID" --reusable --expiration 876000h 2>&1 | grep -v 'WRN\|TRC' | tail -1)
US_KEY=$(docker compose exec -T headscale headscale preauthkeys create --user "$USER_ID" --reusable --expiration 876000h 2>&1 | grep -v 'WRN\|TRC' | tail -1)

echo "=== Updating .env with auth keys ==="

# Preserve original .env and append generated keys
grep -v '^YC_NODE_AUTHKEY\|^US_NODE_AUTHKEY' .env > .env.tmp || true
cat >> .env.tmp <<ENVEOF
YC_NODE_AUTHKEY=${YC_KEY}
US_NODE_AUTHKEY=${US_KEY}
ENVEOF
mv .env.tmp .env
echo "  Updated .env"

echo "=== Restoring full Headscale config with OIDC ==="

cp headscale/config.yaml.full headscale/config.yaml
rm -f headscale/config.yaml.nooidc headscale/config.yaml.full

echo "=== Stopping Headscale (will restart with full stack) ==="

docker compose down

echo "=== Setting up aliases ==="

sudo tee /etc/profile.d/us-node.sh > /dev/null <<ALIASES
# US exit node management
alias us-reset="sudo docker exec docker-us-corp-1 tailscale up --login-server ${CORP_LOGIN_SERVER} --accept-routes --reset --force-reauth"
alias us-up="sudo docker exec docker-us-corp-1 tailscale up --accept-routes --login-server=${CORP_LOGIN_SERVER} --accept-dns=false --exit-node-allow-lan-access --exit-node=${CORP_EXIT_NODE}"
alias us-down="sudo docker exec docker-us-corp-1 tailscale down"
alias us-status="sudo docker exec docker-us-corp-1 tailscale status"
alias us-logs="sudo docker logs --tail 50 docker-us-corp-1"
ALIASES

echo ""
echo "=== Init complete ==="
echo ""
echo "Next steps:"
echo "  1. cd $SCRIPT_DIR && docker compose up -d"
echo "  2. Wait 30s for all services to start"
echo "  3. Approve exit node routes:"
echo "     docker compose exec -T headscale headscale nodes list"
echo "     docker compose exec -T headscale headscale nodes approve-routes --identifier <ID> --routes '0.0.0.0/0,::/0'"
echo "  4. Login to corporate VPN:"
echo "     source /etc/profile.d/us-node.sh"
echo "     us-reset  (open URL in browser)"
echo "     us-up"
