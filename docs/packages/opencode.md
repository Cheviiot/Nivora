# OpenCode

Пакет устанавливает desktop-артефакт OpenCode и wrapper с адаптивным ограничением памяти.

```bash
sudo stplr install nivora/opencode
```

## Запуск

- `opencode-desktop` — основной desktop-wrapper.
- `opencode` и `open-code` — сохранённые upstream-команды.

При наличии `systemd --user` приложение запускается в scope. Лимит `MemoryMax` равен 80% доступной
памяти в диапазоне 6–12 GiB, `MemoryHigh` — 70% от `MemoryMax`. V8 heap ограничивается отдельно в
диапазоне 1–4 GiB. При менее 3 GiB доступной памяти wrapper останавливает запуск.

## Диагностика

```bash
opencode-desktop-doctor
```

Команда показывает размер баз, кэша и крупных SQLite-таблиц, но не изменяет данные.

Перенос desktop-состояния в backup:

```bash
opencode-desktop-reset-state --yes
```

Команда не удаляет файлы безвозвратно. Обычное удаление пакета не затрагивает эти каталоги.
