# Terraform Private Cloud

## Что здесь поднято

1. **Поднял Terraform'ом виртуалку в Yandex Cloud со статическим IP** — `terraform apply`
2. **Поставил Headscale** — self-hosted координационный сервер Tailscale — `scripts/setup-headscale.sh`
3. **Поставил Authelia** — OIDC-провайдер для авторизации по логину/паролю — `scripts/setup-authelia.sh`
4. **Поставил Caddy** — reverse proxy с автоматическим HTTPS (Let's Encrypt) — `scripts/setup-caddy.sh`
5. **Включил встроенный DERP-сервер** — relay WireGuard через HTTPS (встроен в Headscale)
6. **Настроил exit node** — весь трафик устройств идёт через VM — `scripts/setup-exit-node.sh`

## Порядок установки с нуля

```bash
# 1. Поднять VM
cd terraform && tf && terraform apply

# 2. Задать переменные
export VM_IP=$(terraform output -raw vm_external_ip)
export DOMAIN=<DOMAIN>

# 3. Настроить сервисы (порядок важен: caddy → authelia → headscale → exit-node)
ssh ubuntu@$VM_IP "DOMAIN=$DOMAIN bash -s" < scripts/setup-caddy.sh
ssh ubuntu@$VM_IP "DOMAIN=$DOMAIN AUTHELIA_PASSWORD='<PASSWORD>' bash -s" < scripts/setup-authelia.sh
ssh ubuntu@$VM_IP "DOMAIN=$DOMAIN HEADSCALE_OIDC=true bash -s" < scripts/setup-headscale.sh
ssh ubuntu@$VM_IP "DOMAIN=$DOMAIN EXIT_NODE_USER=sergey bash -s" < scripts/setup-exit-node.sh
```

## Подключение клиентов

### Телефон (Android/iOS)

1. Открыть Tailscale → три точки → **Use an alternate server**
2. Ввести `https://<DOMAIN>`
3. Откроется форма логина Authelia — ввести логин/пароль
4. Готово. Выбрать exit node `yc-node` в настройках Tailscale

### Компьютер (Linux/macOS/Windows)

```bash
# Логин (откроет браузер с формой Authelia)
sudo tailscale login --login-server https://<DOMAIN>

# Включить exit node
sudo tailscale set --exit-node=yc-node

# Выключить exit node
sudo tailscale set --exit-node=

# Разлогин
sudo tailscale logout

# Переключение между профилями (если есть корпоративный Tailscale)
tailscale switch --list
sudo tailscale switch <профиль>
```

## Полезные команды на сервере

```bash
ssh ubuntu@<VM_IP>

sudo headscale users list              # список пользователей
sudo headscale nodes list              # подключённые устройства
sudo tailscale status                  # статус exit node и соединений
```

## Terraform

State хранится в Yandex Object Storage (S3-совместимый backend).

```
terraform/
├── bootstrap/   ← одноразовый: создаёт S3 бакет для state
└── ...          ← основной: VM, сеть
```

Первый запуск: [`terraform/bootstrap/README.md`](terraform/bootstrap/README.md)
