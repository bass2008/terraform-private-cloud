# Terraform Private Cloud

## Что здесь поднято

1. **Поднял Terraform'ом виртуалку в Yandex Cloud со статическим IP** — `terraform apply`
2. **Поставил Headscale** — self-hosted координационный сервер Tailscale
3. **Поставил Authelia** — OIDC-провайдер для авторизации по логину/паролю
4. **Поставил Caddy** — reverse proxy с автоматическим HTTPS (Let's Encrypt)
5. **Включил встроенный DERP-сервер** — relay WireGuard через HTTPS (встроен в Headscale)
6. **Настроил exit node `yc-node`** — весь трафик устройств идёт через VM
7. **Настроил exit node `us-node`** — double VPN через второй Tailscale в Docker

Всё поднимается через `docker-compose` — `docker/docker-compose.yml`

## Порядок установки с нуля

```bash
# 1. Подготовить .env
cp docker/.env.example docker/.env
# Отредактировать docker/.env — домен, пользователи, пароли

# 2. Запустить (terraform + docker compose — всё автоматически)
tf && ./setup.sh

# 3. Залогиниться в корпоративный VPN (us-node)
ssh ubuntu@<VM_IP>
source /etc/profile.d/us-node.sh
us-reset    # открыть URL в браузере, залогиниться
us-up
```

## Подключение клиентов

### Телефон (Android/iOS)

1. Открыть Tailscale → три точки → **Use an alternate server**
2. Ввести `https://<DOMAIN>`
3. Откроется форма логина Authelia — ввести логин/пароль
4. Готово. Выбрать exit node:
   - `yc-node` — exit node на VM
   - `us-node` — double VPN

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

## Exit nodes

| Имя | Описание |
|-----|----------|
| `yc-node` | Exit node на VM |
| `us-node` | Double VPN — два Tailscale в Docker-контейнерах |

### Управление us-node (на сервере)

```bash
ssh ubuntu@<VM_IP>
source /etc/profile.d/us-node.sh

us-reset    # переавторизация во втором Tailscale (по необходимости)
us-up       # подключить exit node
us-down     # отключить
us-status   # статус
us-logs     # логи контейнера
```

## Если VM перезагрузилась

```bash
# Все docker-контейнеры стартуют автоматически (restart: always)
# Но us-node нужно переавторизовать:
ssh ubuntu@<VM_IP>
source /etc/profile.d/us-node.sh
us-reset    # открыть URL в браузере, залогиниться
us-up
```

## Полезные команды на сервере

```bash
ssh ubuntu@<VM_IP>

docker compose ps                       # статус контейнеров
docker compose logs <сервис>            # логи сервиса
docker compose exec -T headscale headscale nodes list   # подключённые устройства
docker compose exec -T headscale headscale users list   # пользователи
```

## Terraform

State хранится в Yandex Object Storage (S3-совместимый backend).

```
terraform/
├── bootstrap/   ← одноразовый: создаёт S3 бакет для state
└── ...          ← основной: VM, сеть
```

Первый запуск: [`terraform/bootstrap/README.md`](terraform/bootstrap/README.md)
