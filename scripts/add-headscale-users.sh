#!/bin/bash
set -euo pipefail

###############################################################################
# Add Headscale users and generate pre-auth keys
# Run on the target VM via SSH
#
# Headscale does not support passwords — clients authenticate via pre-auth keys.
# Keys below are reusable and do not expire.
###############################################################################

USERS=("sergey" "victoria")

echo "=== Creating Headscale users ==="

for USER in "${USERS[@]}"; do
  if sudo headscale users list -o json 2>/dev/null | grep -q "\"name\":\"${USER}\""; then
    echo "User '${USER}' already exists — skipping"
  else
    sudo headscale users create "${USER}"
    echo "User '${USER}' created"
  fi
done

echo ""
echo "=== Generating pre-auth keys ==="
echo ""
echo "Use these keys to connect clients (instead of passwords):"
echo "-----------------------------------------------------------"

for USER in "${USERS[@]}"; do
  KEY=$(sudo headscale preauthkeys create --user "${USER}" --reusable --expiration 876000h 2>&1)
  echo "User: ${USER}"
  echo "Key:  ${KEY}"
  echo ""
done

echo "-----------------------------------------------------------"
echo "Save these keys! Use them in Tailscale client to connect."
echo ""
echo "Connection command:"
echo "  tailscale up --login-server http://<VM_EXTERNAL_IP>:8080 --authkey <KEY>"
