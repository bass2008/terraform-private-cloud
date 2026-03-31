#!/bin/bash
set -euo pipefail

###############################################################################
# Full setup: Terraform VM + Docker Compose VPN stack
#
# Prerequisites:
#   - terraform, yc CLI installed
#   - tf function available (sets TF_VAR_* and AWS_* env vars)
#   - docker/.env configured (copy from docker/.env.example)
#   - SSH key added to Yandex Cloud
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/docker/.env" ]; then
  echo "ERROR: docker/.env not found. Copy docker/.env.example to docker/.env and edit it."
  exit 1
fi

echo "=== Step 1: Terraform apply ==="

cd "$SCRIPT_DIR/terraform"
terraform apply -auto-approve
VM_IP=$(terraform output -raw vm_external_ip)
echo "  VM IP: $VM_IP"

echo "=== Step 2: Waiting for SSH ==="

for i in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$VM_IP" "echo ok" &>/dev/null; then
    break
  fi
  echo "  Attempt $i/30..."
  sleep 5
done

echo "=== Step 3: Installing Docker ==="

ssh ubuntu@"$VM_IP" "command -v docker &>/dev/null || (curl -fsSL https://get.docker.com | sh && sudo usermod -aG docker ubuntu)"

echo "=== Step 4: Copying files ==="

scp -r "$SCRIPT_DIR/docker/" ubuntu@"$VM_IP":~/docker/

echo "=== Step 5: Running init ==="

ssh ubuntu@"$VM_IP" "sg docker -c 'bash ~/docker/init.sh'"

echo "=== Step 6: Starting services ==="

ssh ubuntu@"$VM_IP" "sg docker -c 'cd ~/docker && docker compose up -d'"

echo "=== Step 7: Waiting for services ==="

sleep 30

echo "=== Step 8: Approving exit node routes ==="

ssh ubuntu@"$VM_IP" "sg docker -c 'cd ~/docker && docker compose exec -T headscale headscale nodes list -o json'" 2>/dev/null \
  | python3 -c "
import sys, json
nodes = json.load(sys.stdin)
for n in nodes:
    print(n['id'])
" 2>/dev/null | while read NODE_ID; do
  ssh ubuntu@"$VM_IP" "sg docker -c 'cd ~/docker && docker compose exec -T headscale headscale nodes approve-routes --identifier $NODE_ID --routes \"0.0.0.0/0,::/0\"'" 2>/dev/null
  echo "  Approved routes for node $NODE_ID"
done

echo ""
echo "=== Setup complete ==="
echo ""
echo "VM IP: $VM_IP"
echo ""
echo "Next steps:"
echo "  1. Connect client: sudo tailscale login --login-server https://\$(grep DOMAIN $SCRIPT_DIR/docker/.env | cut -d= -f2)"
echo "  2. Setup us-node (corporate VPN):"
echo "     ssh ubuntu@$VM_IP"
echo "     source /etc/profile.d/us-node.sh"
echo "     us-reset   # open URL in browser, login"
echo "     us-up"
