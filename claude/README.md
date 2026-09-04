<p align="center">
  <img src="claude-tray-orange.png" width="96" height="96" alt="Claude">
</p>

<h1 align="center">Claude</h1>

<p align="center">
  Десктопное приложение Anthropic для Claude и сценариев Claude Code
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Custom-lightgrey?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64, arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/claude
```

Пакет заменяет прежнее имя `nivora/claude-desktop` (см. `replaces` в
`Staplerfile`). Исполняемая команда остаётся `/usr/bin/claude-desktop`, чтобы
не конфликтовать с командой `claude` из Claude Code CLI.

## Возможности

Chat, контекст проекта, встроенный терминал, редактор и визуальный просмотр
diff — переупаковка официального DEB из APT-источника Anthropic с сохранением
upstream desktop-id `com.anthropic.Claude`.

## Сетевая изоляция

Claude хранит Chromium-профиль, cookies, browser storage, Crashpad-каталоги и
Cowork VM sockets в пользовательском профиле. Это не сетевая песочница:
приложение обращается к сервисам Anthropic через Интернет, а временный OAuth
callback-сервер использует loopback-порт локальной системы.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
