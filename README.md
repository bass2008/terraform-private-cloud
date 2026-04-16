# Terraform Private Cloud

## What's deployed

1. **Terraform VM in Yandex Cloud with static IP** — `terraform apply`
2. **Headscale** — self-hosted Tailscale coordination server
3. **Authelia** — OIDC provider for login/password authentication
4. **Caddy** — reverse proxy with automatic HTTPS (Let's Encrypt)
5. **Embedded DERP server** — WireGuard relay over HTTPS (built into Headscale)
6. **Exit node `yc-node`** — all client traffic routed through VM
7. **Exit node `us-node`** — double VPN via second Tailscale in Docker

Everything runs via `docker-compose` — `docker/docker-compose.yml`

## Setup from scratch

```bash
# 1. Prepare .env
cp docker/.env.example docker/.env
# Edit docker/.env — domain, users, passwords

# 2. Run (terraform + docker compose — fully automated)
tf && ./setup.sh

# 3. Login to corporate VPN (us-node)
ssh ubuntu@$VM_IP
source /etc/profile.d/us-node.sh
us-reset    # open URL in browser, login
us-up
```

## Connecting clients

### Phone (Android/iOS)

1. Open Tailscale → three dots → **Use an alternate server**
2. Enter `https://<DOMAIN>`
3. Authelia login form will appear — enter username/password
4. Done. Select exit node:
   - `yc-node` — exit node on VM
   - `us-node` — double VPN

### Desktop (Linux/macOS/Windows)

```bash
# Login (opens browser with Authelia form)
sudo tailscale login --login-server https://<DOMAIN>

# Enable exit node
sudo tailscale set --exit-node=yc-node

# Disable exit node
sudo tailscale set --exit-node=

# Logout
sudo tailscale logout

# Switch between profiles (if you have corporate Tailscale)
tailscale switch --list
sudo tailscale switch <profile>
```

## Exit nodes

| Name | Description |
|------|-------------|
| `yc-node` | Exit node on VM |
| `us-node` | Double VPN — two Tailscale instances in Docker containers |

### Managing us-node (on server)

```bash
ssh ubuntu@$VM_IP
source /etc/profile.d/us-node.sh

us-reset    # re-auth second Tailscale (as needed)
us-up       # connect exit node
us-down     # disconnect
us-status   # status
us-logs     # container logs
```

## Diagnostics

```bash
ssh ubuntu@$VM_IP "bash ~/docker/check-relay.sh"

ssh ubuntu@$VM_IP "bash ~/docker/restart-relay.sh"

ssh ubuntu@$VM_IP "bash ~/docker/auth-logs.sh 100"
```

After restart, toggle Tailscale off/on on the phone.

## If VM rebooted

```bash
# All docker containers start automatically (restart: always)
# But us-node needs re-auth:
ssh ubuntu@$VM_IP
source /etc/profile.d/us-node.sh
us-reset    # open URL in browser, login
us-up
```

## Useful commands on server

```bash
ssh ubuntu@$VM_IP

docker compose ps                       # container status
docker compose logs <service>           # service logs
docker compose exec -T headscale headscale nodes list   # connected devices
docker compose exec -T headscale headscale users list   # users
bash ~/docker/auth-logs.sh                              # auth logs (last 20)
bash ~/docker/auth-logs.sh 50                           # auth logs (last 50)
```

## Terraform

State is stored in Yandex Object Storage (S3-compatible backend).

```
terraform/
├── bootstrap/   ← one-time: creates S3 bucket for state
└── ...          ← main: VM, network
```

First run: [`terraform/bootstrap/README.md`](terraform/bootstrap/README.md)
