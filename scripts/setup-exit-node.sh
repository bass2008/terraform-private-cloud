#!/bin/bash
set -euo pipefail

###############################################################################
# Setup VM as Tailscale exit node via Headscale
# Idempotent. Run on the target VM via SSH.
#
# Required env vars:
#   DOMAIN         — e.g. sergey-vpn.crabdance.com
#   EXIT_NODE_USER — headscale user to register under (e.g. sergey)
###############################################################################

DOMAIN="${DOMAIN:?Set DOMAIN before running}"
EXIT_NODE_USER="${EXIT_NODE_USER:?Set EXIT_NODE_USER before running}"

echo "=== Installing Tailscale client ==="

if ! command -v tailscale &> /dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

echo "Tailscale version: $(tailscale version | head -1)"

echo "=== Resolving user ID ==="

USER_ID=$(sudo headscale users list -o json 2>/dev/null \
  | python3 -c "
import sys, json
users = json.load(sys.stdin)
for u in users:
    if u.get('name') == '$EXIT_NODE_USER':
        print(u['id'])
        break
" 2>/dev/null)

if [ -z "$USER_ID" ]; then
  echo "ERROR: User '$EXIT_NODE_USER' not found in headscale"
  sudo headscale users list
  exit 1
fi
echo "  User '$EXIT_NODE_USER' has ID: $USER_ID"

echo "=== Creating pre-auth key ==="

AUTHKEY=$(sudo headscale preauthkeys create --user "$USER_ID" --reusable --expiration 876000h 2>&1 | grep -v 'WRN\|TRC' | tail -1)
echo "  Auth key created"

echo "=== Connecting to Headscale ==="

sudo tailscale up \
  --login-server "https://${DOMAIN}" \
  --authkey "$AUTHKEY" \
  --advertise-yc-node \
  --hostname "yc-node"

echo "=== Approving exit node routes ==="

# Wait for node to appear
sleep 5

# Find node ID
NODE_ID=$(sudo headscale nodes list -o json 2>/dev/null \
  | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
for n in nodes:
    if 'yc-node' in (n.get('given_name',''), n.get('name','')):
        print(n['id'])
        break
" 2>/dev/null)

if [ -z "$NODE_ID" ]; then
  echo "ERROR: Could not find yc-node in headscale nodes list"
  sudo headscale nodes list
  exit 1
fi

echo "  Node ID: $NODE_ID"

# List available routes
echo "  Available routes:"
sudo headscale nodes list-routes --identifier "$NODE_ID" 2>/dev/null

# Approve exit node routes (0.0.0.0/0 and ::/0)
sudo headscale nodes approve-routes --identifier "$NODE_ID" --routes '0.0.0.0/0,::/0'
echo "  Approved routes: 0.0.0.0/0, ::/0"

echo "=== Verifying ==="

sudo headscale nodes list 2>/dev/null

echo ""
echo "=== Exit node is ready ==="
echo ""
echo "To use on client:"
echo "  sudo tailscale set --yc-node=yc-node"
echo ""
echo "To stop routing through exit node:"
echo "  sudo tailscale set --yc-node="
