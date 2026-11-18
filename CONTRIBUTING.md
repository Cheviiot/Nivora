# Участие в Nivora

[Документация](.github/docs/index.md) · [Правила пакетов](.github/docs/package-guide.md)

Nivora сопровождает приложения для **ALT Linux p11**.
Рабочая ветка проекта — **main**. Изменения и автоматические обновления
публикуются в ней; для обычного сопровождения отдельные ветки и PR не создаются.

## Среда разработки

Инструменты, необходимые только для разработки, устанавливайте в Distrobox.
На основной системе остаются контейнерная инфраструктура и пакеты,
необходимые для интеграции с ОС и оборудованием.

```bash
distrobox create --name nivora-dev --image registry.altlinux.org/p11/base
distrobox enter nivora-dev
sudo apt-get update
sudo apt-get install git-core bash python3 curl jq shellcheck sqlite3 rpm-build binutils cpio tar bsdtar appstream desktop-file-utils
git clone https://github.com/Cheviiot/Nivora.git
cd Nivora
git switch main
git pull --ff-only
```

Нужны Python 3.11 или новее и `stplr-spec`. В CI используются ShellCheck 0.9.0,
Go 1.27.4 и закреплённая версия утилит Stapler:
[setup-stplr-spec](.github/actions/setup-stplr-spec/action.yml).
`GOTOOLCHAIN=local` запрещает автоматическую загрузку другой версии Go.
Скрипты подготовки также задают `GOWORK=off`, чтобы внешний `go.work` не менял зависимости
закреплённого checkout. Загрузка зависимостей отделена от проверки и
компиляции; её ограниченные повторы описаны в
[обслуживании](.github/docs/maintenance.md#что-проверяет-полный-прогон).
Относительный `TARGET` отсчитывается от каталога вызова. Готовая утилита
заменяет прежний файл только после успешной проверки запуска.

Если совместимый Go установлен в контейнере, собрать локальный `stplr-spec`
можно так:

```bash
mkdir -p .cache/bin
GOTOOLCHAIN=local STPLR_UTILS_COMMIT=c6ddbb5e4e5637d97bb7b2587729178d715c6c52 \
  .github/tools/prepare_stplr_spec.sh \
  "$PWD/.cache/bin/stplr-spec" \
  https://altlinux.space/stapler/stplr-utils.git
export PATH="$PWD/.cache/bin:$PATH"
```

Полная сборка требует работающего Podman или Docker, доступного из среды запуска.
Скрипты создают собственные одноразовые контейнеры p11; запуск из Distrobox
не заменяет доступ к контейнерному движку. Lifecycle-прогон сейчас поддерживает
только `x86_64`. Полный прогон также
доступен в [GitHub Actions](https://github.com/Cheviiot/Nivora/actions/workflows/clean-build.yml)
на ветке `main`.

### Контейнерный движок

`NIVORA_CONTAINER_ENGINE=docker` или `NIVORA_CONTAINER_ENGINE=podman` явно
выбирает движок для сборки и lifecycle. Без этой переменной GitHub Actions
использует Docker; локально выбирается установленный Podman, а при его
отсутствии — Docker. Выбранный движок должен успешно выполнять `info`.
При ошибке доступа скрипт останавливается: автоматического `sudo` или
перехода к другому движку нет.

Для поддерживаемого прогона stable Stapler v0.2.0 нужен **rootful** движок:
Docker с системным daemon либо Podman, запущенный от root. Rootless-контейнер
может не предоставить диапазоны UID/GID, которые требует вложенная песочница.
Причина и upstream-исправление описаны в
[диагностике](.github/docs/troubleshooting.md#ошибка-uidgid-при-сборке).

Например, для доступного rootful Docker перед проверками выполните:

```bash
docker info
export NIVORA_CONTAINER_ENGINE=docker
```

Сборка и lifecycle сохраняют выбранный Docker context, адрес daemon и TLS
во временной конфигурации вне контекста сборки. Учётные данные реестров образов
и настройки их хранилищ туда не переносятся; исходная конфигурация
пользователя не меняется. `DOCKER_HOST`, `DOCKER_CONTEXT` и явные TLS-параметры
окружения продолжают действовать.

Сохраняйте этот выбор для сборки и последующего lifecycle. Для локального
Podman используйте подготовленную root-сессию с доступными `stplr-spec`
и остальными инструментами; выберите `NIVORA_CONTAINER_ENGINE=podman`
и проверьте `podman info` в этой же сессии. Rootful и rootless Podman имеют
[раздельные хранилища образов и томов](https://docs.podman.io/en/stable/markdown/podman.1.html#root-value).

## Работа с изменением

1. Синхронизируйте `main` и изучите текущие изменения.
2. Проверьте официальное имя приложения, первичный источник загрузки, лицензию
   и наличие зависимостей в p11.
3. Исправьте рецепт и необходимые хуки. При изменении упаковки увеличьте
   `release`; при обновлении приложения измените `version`.
4. Обновите описания по первичным источникам. README служат карточками приложений;
   устройство пакета и диагностику описывайте в [.github/docs](.github/docs/index.md).
5. Синхронизируйте метаданные, выполните проверки и изучите итоговый diff.
6. Опубликуйте commit обычным push в `main`. Если удалённая ветка продвинулась,
   согласуйте изменения и повторите затронутые проверки.

Историю `main` не переписывают. Автоматический publisher тоже отказывается
публиковать кандидат, если исходный SHA уже изменился.

## Проверки

Из корня рабочей копии:

```bash
python3 .github/tools/sync_readme_versions.py
python3 .github/tools/sync_appstream.py
.github/tools/run_checks.sh
git diff --check
```

Для изменённого приложения, например Telegram:

```bash
.github/tools/check_source_availability.sh telegram
stplr-spec verify-checksums --path telegram/Staplerfile
.github/tools/clean_build.sh telegram
.github/tools/verify_artifacts.sh telegram
NIVORA_LIFECYCLE_PACKAGES=telegram .github/tools/test_package_lifecycle.sh
```

`run_checks.sh` проверяет shell/Python, структуру, рецепты, локальные источники,
документационные ссылки и AppStream. Сборка RPM и lifecycle выполняются отдельно.
Изменение общих инструментов требует полного прогона:

```bash
.github/tools/clean_build.sh --all
.github/tools/verify_artifacts.sh --all
.github/tools/test_package_lifecycle.sh
```

Обязательный прогон использует Stapler v0.2.0 на p11.
Для stable используются официальные архивы x86_64 и aarch64 с закреплёнными
SHA-256; наличие ARM-архива не добавляет нативную ARM-проверку в CI.
Дополнительный прогон с закреплённым commit upstream `main` служит ранним
предупреждением. Его pin в [матрице](.github/support-matrix.toml)
не означает отдельную рабочую ветку Nivora.

### Проверка конкретного обновления

Lifecycle запускает свежую установку и обновление в отдельных чистых
контейнерах. По умолчанию для обновления используется синтетический предыдущий
RPM: он проверяет транзакцию и текущие хуки, но не содержит старую версию
приложения и все возможные пользовательские профили.

Если правка касается перехода с конкретного релиза, положите его RPM в
игнорируемый каталог `.cache/previous-rpm/` под именем `имя-пакета.rpm`.
Для Telegram файл должен называться `telegram.rpm`:

```bash
NIVORA_PREVIOUS_ARTIFACTS_DIR="$PWD/.cache/previous-rpm" \
  NIVORA_LIFECYCLE_PACKAGES=telegram \
  .github/tools/test_package_lifecycle.sh
```

Нужен RPM с тем же полным именем пакета, подходящей архитектурой и более
ранней версией, чем проверяемый пакет. При выборе нескольких приложений
предыдущий RPM должен существовать для каждого из них.

## Диагностика upstream без изменения рецептов

Чтобы сравнить текущие и опубликованные версии:

```bash
.github/tools/package_updates.sh check telegram
.github/tools/package_updates.sh check-all
```

`check` выводит текущую и обнаруженную версии одного пакета. `check-all`
также учитывает fingerprints изменяемых источников и показывает статус
каждого приложения. Эти команды не меняют рецепты и не публикуют обновления.

| Код завершения `check-all` | Значение |
|:--|:--|
| `0` | Новых кандидатов нет |
| `10` | Найдено обновление версии или изменяемого источника |
| `1` | Не удалось проверить хотя бы один источник; результаты остальных строк доступны в выводе |

Для ручного обновления используйте штатный
[workflow обслуживания](.github/docs/maintenance.md#ручные-действия-сопровождающего).
Не запускайте публикацию только на основании нового номера: кандидат должен
пройти проверку источников, сборку и lifecycle.

## Как описать результат

Сообщение commit должно объяснять изменение и причину. Значимые изменения
поведения заносите в [CHANGELOG](CHANGELOG.md).
Для ошибки приложите воспроизводимый сценарий в
[Issues](https://github.com/Cheviiot/Nivora/issues).

Различайте выполненные проверки: сборку RPM, установку в контейнере,
запуск графического приложения и вход во внешний сервис.
ARM64 нельзя объявлять полностью проверенной без соответствующего прогона.

Подробные требования — в [правилах пакетов](.github/docs/package-guide.md).
Права CI и обращение с секретами — в [модели доверия](.github/docs/security-model.md).
