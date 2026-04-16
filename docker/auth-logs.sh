#!/bin/bash
###############################################################################
# View Authelia authentication logs
# Run on the VM: bash ~/docker/auth-logs.sh
###############################################################################

cd "$(dirname "$0")"

LIMIT="${1:-20}"

docker run --rm -v docker_authelia_data:/data keinos/sqlite3 \
  sqlite3 /data/db.sqlite3 \
  "SELECT time, CASE successful WHEN 1 THEN 'OK' ELSE 'FAIL' END AS result, username, remote_ip FROM authentication_logs ORDER BY time DESC LIMIT $LIMIT;"
