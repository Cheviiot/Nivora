# Codex

Пакет устанавливает неофициальную Linux-перепаковку Codex Desktop и
предусмотренную Linux-реализацию Computer Use из проектов
[`codex-desktop-linux`](https://github.com/ilysenko/codex-desktop-linux) и
[`computer-use-linux`](https://github.com/agent-sh/computer-use-linux).

В пакет входят:

- приложение `codex-app`;
- bundled plugin `computer-use@openai-bundled`;
- нативный backend `codex-computer-use-linux`, собранный из исходников для
  версии glibc текущего дистрибутива;
- интеграция с AT-SPI, XDG Desktop Portal и доступными средствами ввода Linux.

Патчи не включают серверную возможность в обход Codex. Они добавляют Linux в
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

Команда `setup` идемпотентно включает AT-SPI в текущем пользовательском сеансе;
она изменяет пользовательскую настройку доступности без отдельного запроса.
Разрешения на захват экрана и управление вводом выдаются пользователем через
системные диалоги портала.

## Диагностика

```bash
codex-computer-use-linux doctor
codex-computer-use-linux apps
codex-computer-use-linux windows
```

Если интерфейс всё ещё показывает недоступность, сначала убедитесь, что
установлен пакет Nivora с `release=2` или новее, затем закройте все процессы
Codex и запустите приложение заново.
