<p align="center">
  <img src="https://tailscale.com/favicon.png" width="72" height="72" alt="Tailscale">
</p>

# Tailscale

Tailscale объединяет устройства и сервисы в частную сеть с шифрованием WireGuard. В Linux работа с подключением доступна через командную строку.

[Официальный сайт и описание](https://tailscale.com/) · [Лицензия](LICENSE)

**Платформа:** ALT Linux p11.

**Архитектуры:** amd64 · arm64 (предварительная поддержка).

## Установка

Сначала [подключите Nivora](../.github/docs/installation.md#2-подключить-nivora),
затем выполните:

```bash
sudo stplr install nivora/tailscale
```

Текущая версия указана в [каталоге](../README.md#каталог).
[Обновление и удаление](../.github/docs/installation.md) выполняются через Stapler.

## Состояние подключения

Проверка текущего подключения:

```bash
tailscale status
```

Первый вход и дополнительные настройки описаны в [руководстве по Tailscale](../.github/docs/troubleshooting.md#tailscale-первый-вход-и-настройки).

[Каталог Nivora](../README.md) · [Помощь](../.github/docs/troubleshooting.md)
