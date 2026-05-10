---
server_url: https://${DOMAIN}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090

grpc_listen_addr: 0.0.0.0:50443
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
  magic_dns: false
  override_local_dns: false
  base_domain: personal.tail
  nameservers:
    global: []

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
    method: S256
