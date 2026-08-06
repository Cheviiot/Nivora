<p align="center">
  <img src="https://tailscale.com/favicon.png" width="96" height="96" alt="Tailscale">
</p>

<h1 align="center">Tailscale</h1>

<p align="center">
  Mesh VPN на базе WireGuard
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-blue?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64, arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/tailscale
```

## Возможности

[Tailscale](https://tailscale.com) — безопасный mesh VPN на базе WireGuard и
identity-based access для соединения устройств и сервисов между сетями.

## Технические детали

Пакет ставит и включает системный сервис `tailscaled.service`. После
установки пользователь, от имени которого выполнялась команда (через `sudo`,
`pkexec` или `logname`), автоматически назначается Tailscale operator — это
позволяет управлять соединением командой `tailscale` без повторного `sudo`
для каждой операции.

### Полная очистка данных

Обычное удаление пакета не трогает состояние сети и авторизацию. Для
намеренного полного сброса — выхода из сети и удаления локального состояния
(`/var/lib/tailscale`, кеша, unit-файлов и логов) — предусмотрена отдельная
команда, требующая явного подтверждения:

```bash
sudo tailscale-purge-data --yes
```

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
