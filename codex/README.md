<p align="center">
  <img src="codex-app.png" width="96" height="96" alt="Codex">
</p>

<h1 align="center">Codex</h1>

<p align="center">
  Неофициальная Linux-перепаковка десктопного приложения Codex
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Custom-lightgrey?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64-2ea043?style=for-the-badge" alt="amd64">
</p>

---

## Установка

```bash
sudo stplr install nivora/codex
```

## Возможности

Пакет собирает приложение `codex-app` и предусмотренную Linux-реализацию
Computer Use из [`codex-desktop-linux`](https://github.com/ilysenko/codex-desktop-linux)
и [`computer-use-linux`](https://github.com/agent-sh/computer-use-linux):

- bundled plugin `computer-use@openai-bundled`;
- нативный backend `codex-computer-use-linux`, собранный из исходников под
  версию glibc текущего дистрибутива;
- интеграция с AT-SPI, XDG Desktop Portal и доступными средствами ввода Linux.

Патчи не включают серверную возможность в обход Codex — они добавляют Linux в
список поддерживаемых локальных платформ и сохраняют проверку feature gate
`computer_use`, которую возвращает сервис.

## Первичная настройка

После установки полностью перезапустите Codex. Состояние backend проверяется
без изменения системы:

```bash
codex-computer-use-linux doctor
```

Рекомендуемую настройку доступности и ввода выполняет upstream-мастер:

```bash
codex-computer-use-linux setup
```

Для получения списка окон в GNOME может понадобиться отдельная настройка
расширения:

```bash
codex-computer-use-linux setup-window-targeting
```

Команда `setup` идемпотентно включает AT-SPI в текущем пользовательском
сеансе; она изменяет пользовательскую настройку доступности без отдельного
запроса. Разрешения на захват экрана и управление вводом выдаются
пользователем через системные диалоги портала.

## Диагностика

```bash
codex-computer-use-linux doctor
codex-computer-use-linux apps
codex-computer-use-linux windows
```

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
