#!/bin/bash
set -euo pipefail

###############################################################################
# Setup two Docker containers for US exit node:
#   us-corp  — connects to corporate Tailscale, exits via EU
#   us-node  — connects to Headscale, advertises as exit node for phone
#              routes all traffic through us-corp
#
# Idempotent. Run on the target VM via SSH.
#
# Required env vars:
#   DOMAIN         — e.g. sergey-vpn.crabdance.com
#   EXIT_NODE_USER — headscale user (e.g. sergey)
###############################################################################

DOMAIN="${DOMAIN:?Set DOMAIN before running}"
EXIT_NODE_USER="${EXIT_NODE_USER:?Set EXIT_NODE_USER before running}"

echo "=== Installing Docker ==="

if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker ubuntu
fi

echo "Docker version: $(docker --version)"

echo "=== Creating Docker network ==="

sudo docker network create us-net 2>/dev/null || true

echo "=== Stopping old containers ==="

sudo docker rm -f us-tailscale us-tailscale-tmp us-corp us-node 2>/dev/null || true

echo "=== Starting us-corp (corporate Tailscale → EU exit) ==="

sudo docker run -d \
  --name us-corp \
  --network us-net \
  --restart=always \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --device=/dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 \
  -v us-corp-state:/var/lib/tailscale \
  tailscale/tailscale:latest

sleep 5

# Enable NAT in us-corp so us-node traffic can go through it
sudo docker exec us-corp sh -c "iptables -t nat -A POSTROUTING -o tailscale0 -j MASQUERADE 2>/dev/null || true"
sudo docker exec us-corp sh -c "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true"

CORP_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' us-corp)
echo "  us-corp IP: $CORP_IP"

echo "=== Creating Headscale pre-auth key ==="

USER_ID=$(sudo headscale users list -o json 2>/dev/null \
  | python3 -c "
import sys, json
users = json.load(sys.stdin)
for u in users:
    if u.get('name') == '$EXIT_NODE_USER':
        print(u['id'])
        break
" 2>/dev/null)

AUTHKEY=$(sudo headscale preauthkeys create --user "$USER_ID" --reusable --expiration 876000h 2>&1 | grep -v 'WRN\|TRC' | tail -1)
echo "  Auth key created"

echo "=== Starting us-node (Headscale exit node → routes via us-corp) ==="

sudo docker run -d \
  --name us-node \
  --network us-net \
  --restart=always \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --device=/dev/net/tun \
  --env TS_EXTRA_ARGS="--login-server=https://${DOMAIN} --authkey=${AUTHKEY} --advertise-exit-node --hostname=us-node" \
  --env TS_STATE_DIR=/var/lib/tailscale \
  -v us-node-state:/var/lib/tailscale \
  tailscale/tailscale:latest

sleep 5

# Set default route through us-corp
sudo docker exec us-node sh -c "ip route del default 2>/dev/null || true; ip route add default via $CORP_IP"

echo "=== Approving us-node exit routes in Headscale ==="

sleep 5

NODE_ID=$(sudo headscale nodes list -o json 2>/dev/null \
  | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
for n in nodes:
    if 'us-node' in (n.get('given_name',''), n.get('name','')):
        print(n['id'])
        break
" 2>/dev/null)

if [ -n "$NODE_ID" ]; then
  sudo headscale nodes approve-routes --identifier "$NODE_ID" --routes '0.0.0.0/0,::/0'
  echo "  Routes approved for us-node (ID: $NODE_ID)"
else
  echo "  WARNING: us-node not yet registered, approve manually later"
fi

echo "=== Setting up aliases ==="

sudo tee /etc/profile.d/us-node.sh > /dev/null <<'ALIASES'
# US exit node management
alias us-reset="sudo docker exec us-corp tailscale up --login-server https://vpn.invent.us --accept-routes --reset --force-reauth"
alias us-up="sudo docker exec us-corp tailscale up --accept-routes --login-server=https://vpn.invent.us --exit-node-allow-lan-access --exit-node=apptrium-prod-vm-eu-1"
alias us-down="sudo docker exec us-corp tailscale down"
alias us-status="sudo docker exec us-corp tailscale status"
alias us-logs="sudo docker logs --tail 50 us-corp"
ALIASES

echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. SSH to VM:  ssh ubuntu@<VM_IP>"
echo "  2. source /etc/profile.d/us-node.sh"
echo "  3. us-reset   (get login URL, open in browser)"
echo "  4. us-up       (connect to EU exit node)"
echo ""
echo "On phone: select exit node 'us-node' for YouTube"
