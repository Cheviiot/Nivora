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

Nivora CLI упрощает установку, удаление, обновление и поиск пакетов,
управление репозиториями и диагностику системы.

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

Основная команда принимает и полные названия операций:

```bash
nv install chatgpt
nv search editor
nv info chatgpt
nv repo list
```

## Репозитории

Короткое имя автоматически получает префикс `nivora`:

```bash
nvi chatgpt                  # stplr install nivora/chatgpt
nvi other/package          # stplr install other/package
```

Репозиторий можно изменить или отключить:

```bash
nvi --repo other package
nvi --repo none package
NIVORA_REPO=other nvi package
```

Локальные пути и файлы пакетов никогда не получают префикс.

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

Изменяющие систему операции запускаются через `sudo`. Другую команду
повышения привилегий можно задать в `NIVORA_SUDO`. Аргументы передаются
массивом без вычисления shell-строк. Параметр `--dry-run` показывает итоговую
команду без её выполнения.

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
