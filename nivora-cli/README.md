<p align="center">
  <img src="../.github/assets/nivora.png" width="96" height="96" alt="Nivora CLI">
</p>

<h1 align="center">Nivora CLI</h1>

<p align="center">
  Удобная многоязычная оболочка для Stapler
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-brightgreen?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-all-2ea043?style=for-the-badge" alt="all">
</p>

---

## Установка

```bash
sudo stplr install nivora/nivora-cli
```

Nivora CLI упрощает повседневные операции, но не скрывает возможности Stapler:
все публичные команды стабильного Stapler доступны через `nv`, а `nv raw`
передаёт аргументы без преобразований. Требуется Stapler `v0.1.1` или новее.

## Интерактивный режим

Команда `nv` без аргументов открывает компактное меню:

```text
╭─ NIVORA ─────────────────────────────╮
│ Простое управление пакетами Stapler  │
╰──────────────────────────────────────╯

  Пакеты
  [i] Установить          nvi
  [e] Удалить             nve
  [u] Обновить             nvu
  [s] Найти                nvs
  [q] Информация           nvqi
  [a] Все пакеты           nvqa

  Система
  [r] Обновить репозитории nvr
  [l] Репозитории          nvrl
  [f] Исправить            nvf
  [d] Диагностика          nvd
```

В конвейере или другом неинтерактивном окружении `nv` выводит обычную справку.

## Короткие команды

| Команда | Операция Stapler |
|:--|:--|
| `nvi package` | установить `nivora/package` |
| `nve package` | удалить `nivora/package` |
| `nvu` | обновить установленные пакеты |
| `nvs query` | найти пакет |
| `nvqi package` | показать информацию о пакете |
| `nvqa` | показать каталог пакетов |
| `nvr` | обновить индексы репозиториев |
| `nvrl` | показать подключённые репозитории |
| `nvf` | исправить состояние Stapler |
| `nvd` | проверить окружение |
| `nvc` | показать или изменить конфигурацию Stapler |

Основная команда принимает полный набор операций стабильного Stapler:

| Команды | Назначение |
|:--|:--|
| `install`, `remove`, `upgrade`, `info`, `list`, `search` | операции с пакетами и каталогом |
| `build`, `helper` | сборка Staplerfile и запуск helper-функции |
| `refresh`, `fix`, `migrate` | обслуживание индекса и состояния Stapler |
| `repo`, `config`, `support`, `version` | репозитории, настройки и сведения о среде |
| `raw` | точная передача оставшихся аргументов в `stplr` |

Примеры:

```bash
nv install chatgpt
nv search editor
nv info chatgpt
nv repo list
nv build --package nivora/chatgpt
nv helper list
nv migrate
nv support
nv raw repo list --json
```

`raw` не добавляет префикс репозитория и не выбирает привилегии за пользователя:
правила самой команды `stplr` остаются без изменений. Глобальные параметры Nivora
нужно отделять через `--`, если их требуется передать Stapler буквально.

## Репозитории

Короткое имя автоматически получает префикс `nivora`:

```bash
nvi chatgpt                # stplr install nivora/chatgpt
nvi other/package          # stplr install other/package
```

Старое имя `codex` оставлено только как совместимый ввод. Команды установки,
удаления и просмотра информации заменяют `codex` на `chatgpt` и печатают
предупреждение; автодополнение предлагает все 16 активных package ID.

Репозиторий можно изменить или отключить:

```bash
nvi --repo other package
nvi --repo none package
NIVORA_REPO=other nvi package
```

Локальные пути и файлы пакетов никогда не получают префикс.

После подключения или изменения репозитория индекс обновляется только явной
командой `sudo stplr refresh`. Nivora CLI намеренно не полагается на `autoPull`
и не запускает обновление скрыто.

## Язык и оформление

Русский или английский язык выбирается по системной локали. Явное
переопределение:

```bash
nv --lang en help
NIVORA_LANG=ru nvd
```

Цветной вывод включается только для терминала. Его можно отключить
стандартной переменной `NO_COLOR`, параметром `--no-color` или значением
`NIVORA_COLOR=never`.

## Безопасность

Системные операции (`install`, `remove`, `upgrade`, `refresh`, `fix`, `migrate`,
изменение `repo` и `config set`) запускаются через `sudo`. `build` всегда идёт от
обычного пользователя: Stapler сам изолирует сборку, а артефакты не становятся
root-owned. Другую команду повышения привилегий можно задать в `NIVORA_SUDO`.
Аргументы передаются массивом без вычисления shell-строк. Параметр `--dry-run`
показывает итоговую команду без её выполнения.

`nvd`/`nv doctor` выполняет только read-only проверки: находит Stapler и
поддерживаемый системный package manager, сверяет минимальную версию, наличие
команды повышения привилегий, подключение выбранного репозитория и доступность
`nivora/nivora-cli` в локальном индексе. Диагностика никогда не вызывает
`refresh`, `fix` или `migrate`; если индекс отсутствует, она показывает точную
команду ручного обновления.

| Переменная | Назначение |
|:--|:--|
| `NIVORA_LANG` | язык интерфейса: `ru` или `en` |
| `NIVORA_REPO` | репозиторий коротких имён |
| `NIVORA_SUDO` | команда повышения привилегий |
| `NIVORA_COLOR` | режим цвета; `never` отключает цвет |
| `NIVORA_QUIET=1` | не печатать запускаемую команду |
| `NO_COLOR` | стандартное отключение цвета |

Автодополнение для Bash, Fish или Zsh генерируется командой
`nv completion <shell>`.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
