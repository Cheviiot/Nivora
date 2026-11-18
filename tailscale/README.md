# Tailscale

Tailscale соединяет устройства в частную сеть через WireGuard. В Linux подключением управляет служба `tailscaled`, а команда `tailscale` позволяет войти в сеть и увидеть доступные устройства. [Tailscale для Linux](https://tailscale.com/docs/install/linux)

ALT Linux p11 · x86_64 · aarch64 (предварительная поддержка)

## Установка

**Лицензия** клиента и службы — [BSD-3-Clause](https://github.com/tailscale/tailscale/blob/main/LICENSE). Для учётной записи в облаке действуют [условия сервиса](https://tailscale.com/legal/terms).

```bash
sudo stplr install nivora/tailscale
```

## Первое подключение

При первой установке пакет включает и запускает `tailscaled.service` через systemd. Подключите устройство к сети и пройдите авторизацию по ссылке, которую напечатает команда.

```bash
sudo tailscale up
```

Посмотреть устройства можно командой `tailscale status`. Если хотите управлять подключением от своего пользователя, **после первого входа** назначьте его оператором из обычного пользовательского терминала.

```bash
sudo tailscale set --operator="$USER"
```

## Настройки и сброс

Параметры службы находятся в `/etc/default/tailscaled`, состояние и ключи узла — в `/var/lib/tailscale`. Обычное удаление пакета сохраняет авторизацию. Для **полного сброса** выполните `sudo tailscale-purge-data --yes`, пока пакет установлен. Команда остановит службу и необратимо удалит локальное состояние. При следующем подключении понадобится новый вход.

[Подключение Nivora](../.github/docs/installation.md) · [Каталог приложений](../README.md)
