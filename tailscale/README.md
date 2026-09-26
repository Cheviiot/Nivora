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

## Состав пакета

Состав файлов совпадает с официальной поставкой Tailscale:

| Путь | Назначение |
|:--|:--|
| `/usr/bin/tailscale` | клиент командной строки |
| `/usr/sbin/tailscaled` | демон узла |
| `/etc/default/tailscaled` | `PORT` и `FLAGS` демона, сохраняется при обновлении |
| `/usr/lib/systemd/system/tailscaled.service` | сам сервис |
| `/usr/lib/systemd/system/tailscale-wait-online.service` | ожидание подключения |
| `/usr/lib/systemd/system/tailscale-online.target` | цель «Tailscale в сети» |
| `/var/cache/tailscale` | кеш демона, удаляется вместе с пакетом |

### Запуск других служб после подключения

`tailscale-online.target` — штатный способ упорядочить свою службу так, чтобы
она стартовала уже после установления соединения:

```ini
[Unit]
After=tailscale-online.target
Wants=tailscale-online.target
```

Цель не активна по умолчанию; включите её, если она нужна:

```bash
sudo systemctl enable tailscale-online.target
```

## Технические детали

Пакет ставит и включает системный сервис `tailscaled.service`. Официальный
RPM Tailscale вместо этого вызывает `systemctl preset`, но политика ALT
заканчивается правилом `disable *` — после такой установки демон остался бы
выключенным. Поэтому при **первой** установке сервис включается явно, как это
делает официальный `.deb`. Обновление пакета сервис заново не включает: если
вы его отключили, он останется отключённым, а работающий будет перезапущен на
новый бинарник.

После первой установки пользователь, от имени которого выполнялась команда
(через `sudo`, `pkexec` или `logname`), автоматически назначается Tailscale
operator — это позволяет управлять соединением командой `tailscale` без
повторного `sudo` для каждой операции. При обновлении назначение не
повторяется.

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
