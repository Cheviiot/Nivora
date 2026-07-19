# Claude Desktop

Пакет `claude-desktop` переупаковывает DEB из APT-источника Anthropic и сохраняет upstream
desktop-id `com.anthropic.Claude`.

```bash
sudo stplr install nivora/claude-desktop
```

## Два независимых приложения

- `claude-desktop` и `claude-code-desktop` запускают основное приложение Claude.
- `claude-alt` и `claude-code-alt` запускают отдельное приложение ClaudeAlt.
- `claude-desktop-account2` и `claude-code-desktop-account2` сохранены как совместимые
  алиасы ClaudeAlt.
- Команда `claude` не создаётся, чтобы не конфликтовать с Claude Code CLI.

ClaudeAlt имеет отдельные executable/resources tree, Electron `productName`, Wayland `app_id`,
X11 `WM_CLASS`, desktop-файл, Chromium-профиль, Cowork VM socket, оконную и
tray-иконки. Поэтому окружение рабочего стола группирует Claude и ClaudeAlt как
разные приложения, а `requestSingleInstanceLock()` и Cowork runtime каждого
приложения работают независимо.

Новая установка ClaudeAlt хранит cookies, OAuth, IndexedDB и Chromium locks в
`${XDG_CONFIG_HOME:-~/.config}/ClaudeAlt`. Если уже существует прежний каталог
`${XDG_CONFIG_HOME:-~/.config}/Claude-Account-2`, launcher использует его, чтобы после обновления
не потерять авторизацию второго аккаунта. Глобальные данные Claude Code в `~/.claude` могут
по-прежнему использоваться обоими приложениями.

## Настройка

| Переменная | Назначение |
|:--|:--|
| `CLAUDE_ALT_DATA_DIR` | Явно задать каталог профиля ClaudeAlt |
| `CLAUDE_DESKTOP_ACCOUNT2_DIR` | Совместимое имя переменной прежнего второго профиля |
| `CLAUDE_ALT_EXECUTABLE` | Переопределить executable ClaudeAlt для диагностики |

Основной Claude продолжает использовать upstream desktop-id `com.anthropic.Claude`, а ClaudeAlt
использует `com.anthropic.ClaudeAlt`.
