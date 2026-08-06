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

## Два независимых пакета

[ClaudeAlt](../claude-alt/README.md) — отдельный пакет для второй,
полностью независимой установки: свой executable/resources tree, Electron
`productName`, Wayland `app_id`, X11 `WM_CLASS`, desktop-файл, Chromium-профиль
и Cowman VM socket. В системном лотке используется штатный глиф Claude:
оранжевый у основного приложения, бирюзовый — у ClaudeAlt. Большие app-иконки
окон при этом остаются отдельными, поэтому окружение рабочего стола
группирует Claude и ClaudeAlt как разные приложения, а
`requestSingleInstanceLock()` и Cowork runtime каждого приложения работают
независимо.

## Сетевая изоляция

Claude и ClaudeAlt имеют разные Chromium-профили, single-instance sockets,
cookies, browser storage, Crashpad-каталоги и Cowork VM sockets. Временные
OAuth callback-серверы по умолчанию получают свободный loopback-порт от ОС.

Это не сетевые песочницы: оба приложения выходят в Интернет с одного хоста и
публичного IP-адреса. Общий `claude://` URL handler намеренно остаётся за
основным Claude.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
