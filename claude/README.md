# Claude Desktop

Настольное приложение Anthropic объединяет чат Claude, работу с файлами в Cowork и разработку в Claude Code. В Claude Code можно вести несколько сессий и просматривать изменения в коде. [Руководство Anthropic для Linux](https://code.claude.com/docs/en/desktop-linux)

ALT Linux p11 · x86_64 · aarch64 (предварительная поддержка)

## Установка

**Лицензия приложения** — проприетарная. При интерактивной сборке Stapler показывает [условия Anthropic для индивидуальных пользователей](https://www.anthropic.com/legal/consumer-terms) и запрашивает подтверждение.

```bash
sudo stplr install nivora/claude
```

## Запуск

Откройте Claude из меню или выполните `claude-desktop`. Задачи Cowork выполняются в виртуальной машине. Для этого режима нужны QEMU, доступ к KVM и включённая в прошивке аппаратная виртуализация. [Требования Cowork](https://code.claude.com/docs/en/desktop-linux#cowork-requirements)

[Подключение Nivora](../.github/docs/installation.md) · [Каталог приложений](../README.md)
