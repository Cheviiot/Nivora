# Claude Desktop

Пакет `claude-desktop` переупаковывает DEB из APT-источника Anthropic и сохраняет upstream
desktop-id `com.anthropic.Claude`.

```bash
sudo stplr install nivora/claude-desktop
```

## Команды и профили

- `claude-desktop` и `claude-code-desktop` запускают основной профиль.
- `claude-desktop-account2` и `claude-code-desktop-account2` запускают второй профиль.
- Команда `claude` не создаётся, чтобы не конфликтовать с Claude Code CLI.

Второй профиль хранит cookies, OAuth, IndexedDB и Chromium locks в
`${XDG_CONFIG_HOME:-~/.config}/Claude-Account-2`. Локальные проекты, `~/.claude`, MCP-конфигурация и
сессии Claude Code доступны обоим профилям. Облачные чаты и память остаются привязаны к
конкретной учётной записи Anthropic.

## Настройка

| Переменная | Назначение |
|:--|:--|
| `CLAUDE_DESKTOP_PRIMARY_DIR` | Каталог основного профиля |
| `CLAUDE_DESKTOP_ACCOUNT2_DIR` | Каталог второго профиля |
| `CLAUDE_DESKTOP_ACCOUNT2_SHARE_LOCAL_DATA=0` | Отключить общий локальный слой |

Переименование package ID не меняет эти пути и не создаёт вторые desktop-ярлыки.
