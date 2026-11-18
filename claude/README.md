# Claude Desktop

Настольное приложение Anthropic объединяет чат Claude, работу с файлами в Cowork и разработку в Claude Code. В Claude Code можно вести несколько сессий и просматривать изменения в коде. [Руководство Anthropic для Linux](https://code.claude.com/docs/en/desktop-linux)

ALT Linux p11 · x86_64 · aarch64 (предварительная поддержка)

## Установка

**Лицензия приложения** — проприетарная. При интерактивной сборке Stapler показывает [условия Anthropic для индивидуальных пользователей](https://www.anthropic.com/legal/consumer-terms) и запрашивает подтверждение.

```bash
sudo stplr install nivora/claude
```

## Запуск

Откройте Claude из меню или выполните `claude-desktop`.

## Cowork

Cowork выполняет задачи в виртуальной машине с аппаратной виртуализацией KVM. Если планируете пользоваться этим режимом, узнайте архитектуру командой `uname -m` и установите пакеты для неё.

| Архитектура | Команда для ALT p11 |
| --- | --- |
| x86_64 | `sudo apt-get install qemu-system-x86-core virtiofsd` |
| aarch64 | `sudo apt-get install qemu-system-aarch64-core virtiofsd` |

APT установит прошивку UEFI вместе с QEMU. Для обмена файлами с виртуальной машиной Claude использует системный `virtiofsd`. Пользователю нужен доступ на чтение и запись к `/dev/kvm` и `/dev/vhost-vsock`. [Требования Cowork](https://code.claude.com/docs/en/desktop-linux#cowork-requirements)

[Подключение Nivora](../.github/docs/installation.md) · [Каталог приложений](../README.md)
