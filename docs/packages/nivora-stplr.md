# Nivora Stapler Helper

`nivora-stplr` добавляет короткие команды для Stapler и мигратор прежних пакетов.

```bash
sudo stplr install nivora/nivora-stplr
```

## Команды

| Alias | Вызов Stapler |
|:--|:--|
| `sli` | `sudo stplr install` |
| `slr` | `sudo stplr remove` |
| `slu` | `sudo stplr up` |
| `slf` | `sudo stplr fix` |
| `slref` | `sudo stplr refresh` |
| `sls` | `stplr search` |
| `slii` | `stplr info` |
| `sll` | `stplr list` |
| `sl` | Диспетчер тех же команд |

Примеры:

```bash
sli --repo nivora parsec
slii nivora/codex
slu --clean
```

Короткое имя пакета не привязывается к Nivora по умолчанию. Префикс задаётся явно:

```bash
export NIVORA_STPLR_REPO=nivora
```

| Переменная | Назначение |
|:--|:--|
| `NIVORA_STPLR_REPO` | Префикс для коротких package names |
| `NIVORA_STPLR_SUDO` | Команда повышения привилегий, по умолчанию `sudo` |
| `NIVORA_STPLR_QUIET=1` | Не печатать команду перед запуском |

Helper не передаёт произвольные shell-строки через `sudo`. Миграция описана в
[docs/migration-from-luma.md](../migration-from-luma.md).
