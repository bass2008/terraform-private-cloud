#!/bin/bash
###############################################################################
# Diagnose DERP relay — check if connections are healthy
# Run on the VM: bash ~/docker/check-relay.sh
###############################################################################

cd "$(dirname "$0")"

echo "=== Containers ==="
docker compose ps --format "table {{.Name}}\t{{.Status}}"

echo ""
echo "=== Memory ==="
free -h | head -2

echo ""
echo "=== DERP endpoint ==="
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$(grep DOMAIN .env | cut -d= -f2)/derp 2>/dev/null)
echo "  /derp response: $HTTP_CODE (426 = OK)"

echo ""
echo "=== Headscale nodes ==="
docker compose exec -T headscale headscale nodes list 2>/dev/null

echo ""
echo "=== Client connection stability (last 1h) ==="
echo "  Look for frequent connect/disconnect = flaky network on client"
docker compose logs headscale --since 1h 2>&1 \
  | grep -E "Node (connected|disconnected)" \
  | grep -oP '\S+ \S+.*node\.name=\S+' \
  | awk '{print $1, $2, $NF}' \
  | sort | uniq -c | sort -rn | head -20
echo ""
echo "  Recent events:"
docker compose logs headscale --since 30m 2>&1 \
  | grep -E "Node (connected|disconnected)" \
  | awk '{print $2, $3, $(NF-1), $NF}' \
  | tail -15

echo ""
echo "=== yc-node connectivity ==="
echo -n "  ping 8.8.8.8: "
docker exec docker-yc-node-1 ping -c1 -W3 8.8.8.8 2>&1 | grep -oP '\d+\.?\d* ms' | head -1 || echo "FAIL"

echo ""
echo "=== us-node connectivity ==="
echo -n "  ping 8.8.8.8: "
docker exec docker-us-node-1 ping -c1 -W3 8.8.8.8 2>&1 | grep -oP '\d+\.?\d* ms' | head -1 || echo "FAIL"
echo -n "  route via us-corp: "
docker exec docker-us-node-1 ip route show default 2>&1

echo ""
echo "=== us-corp status ==="
docker exec docker-us-corp-1 tailscale status 2>&1 | grep -E "exit node|offers" || echo "  Not connected to corporate VPN (run us-reset + us-up)"

echo ""
echo "=== Errors in headscale logs (last 1h) ==="
docker compose logs headscale --since 1h 2>&1 | grep -iE "error|fatal" | grep -v "invalid hostname" | tail -10 || echo "  No errors"
