<p align="center">
  <img src="../claude/claude-alt.png" width="96" height="96" alt="ClaudeAlt">
</p>

<h1 align="center">ClaudeAlt</h1>

<p align="center">
  Независимая вторая установка Claude Desktop
</p>

<p align="center">
  <a href="../claude/LICENSE"><img src="https://img.shields.io/badge/license-Custom-lightgrey?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64, arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/claude-alt
```

Самостоятельная вторая установка [Claude](../claude/README.md), не входящая в
пакет `claude`. Использует собственные runtime, профиль и desktop-идентичность
(`com.anthropic.ClaudeAlt`); иконки Nivora переносятся без изменений.
`claude` и `claude-alt` можно устанавливать, обновлять и удалять независимо
друг от друга.

## Профиль и данные

Новая установка хранит cookies, OAuth, IndexedDB и Chromium locks в
`${XDG_CONFIG_HOME:-~/.config}/ClaudeAlt`. Если уже существует прежний
каталог `${XDG_CONFIG_HOME:-~/.config}/Claude-Account-2`, launcher использует
его, чтобы после обновления не потерять авторизацию второго аккаунта.
Глобальные данные Claude Code в `~/.claude` по-прежнему доступны обоим
приложениям.

## Настройка

| Переменная | Назначение |
|:--|:--|
| `CLAUDE_ALT_DATA_DIR` | Явно задать каталог профиля ClaudeAlt |
| `CLAUDE_DESKTOP_ACCOUNT2_DIR` | Совместимое имя переменной прежнего второго профиля |
| `CLAUDE_ALT_EXECUTABLE` | Переопределить executable ClaudeAlt для диагностики |

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
