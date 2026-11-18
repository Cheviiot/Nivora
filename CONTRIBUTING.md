# Работа с пакетами Nivora

Сопровождение идёт в `main`. Nivora собирает пакеты для ALT Linux p11 через Stapler. Для установки приложений перейдите в [руководство пользователя](.github/docs/installation.md).

## Подготовить среду

Создайте контейнер p11 для разработки. В нём установите зависимости и получите рабочую копию.

```bash
distrobox create --name nivora-dev --image registry.altlinux.org/p11/base
distrobox enter nivora-dev
sudo apt-get update
sudo apt-get install git-core bash python3 curl jq shellcheck sqlite3 rpm-build binutils cpio tar bsdtar appstream desktop-file-utils
git clone https://github.com/Cheviiot/Nivora.git
cd Nivora
```

Проверкам нужны Python 3.11+ и `stplr-spec`. При установленном совместимом Go закреплённый инструмент можно собрать той же командой, что и в CI. [Версии инструментов](.github/actions/setup-stplr-spec/action.yml)

```bash
mkdir -p .cache/bin
GOTOOLCHAIN=local STPLR_UTILS_COMMIT=c6ddbb5e4e5637d97bb7b2587729178d715c6c52 \
  .github/tools/prepare_stplr_spec.sh "$PWD/.cache/bin/stplr-spec" \
  https://altlinux.space/stapler/stplr-utils.git
export PATH="$PWD/.cache/bin:$PATH"
```

Для локальной сборки RPM на x86_64 нужен доступ к rootful Docker или Podman. Проверьте `docker info` или `podman info` в той же сессии, затем задайте `NIVORA_CONTAINER_ENGINE=docker` или `podman` через `export`. Это даёт вложенной песочнице Stapler нужный диапазон UID/GID. Тот же полный прогон доступен в [GitHub Actions](https://github.com/Cheviiot/Nivora/actions/workflows/clean-build.yml).

## Подготовить пакет

- **Рецепт.** Имя каталога совпадает с `name` в `Staplerfile`. Укажите `compatible_with=('altlinux_p11')`, архитектуры с доступными сборками и зависимости из p11. Версию берите у разработчика. При изменении упаковки той же версии увеличьте `release`.
- **Источники и права.** Задайте официальный HTTPS-адрес для каждой архитектуры, полный commit для снимка и SHA-256 для каждого источника, включая `local:///`. В `license` укажите SPDX или `LicenseRef-*`, а для проприетарного приложения заполните `nonfree=1`, `nonfree_msg` и `nonfree_url`. При первой установке RPM выведите название лицензии и путь к материалам в `/usr/share/licenses/<пакет>/`. Для примера см. [Telegram](telegram/postinstall.sh) и [Parsec](parsec/postinstall.sh). Проприетарные установщики скачиваются с серверов разработчиков. Публикуйте в Nivora только рецепт и файлы упаковки.
- **Состав RPM.** Перечислите файлы в `files()`. Для сохраняемой конфигурации путь в `backup` должен точно совпадать с путём в `files()`. При обновлении хуки сохраняют настройки пользователя и состояние служб. Для пакета с собственными библиотеками проверьте зависимости и владельцев файлов в готовом RPM.
- **Карточка.** В README пакета дайте назначение, лицензию рядом с командой установки, первый запуск и нужные только этому приложению особенности. Сохраните заголовок «Установка» для ссылок из витрины. У графических приложений сверяйте AppStream ID, desktop-файл и иконку.
- **Новый пакет.** Добавьте запись в [матрицу](.github/support-matrix.toml), [валидатор](.github/tools/validate_repo.py), [проверку версий](.github/tools/package_updates.sh) и [проверку установки](.github/tools/test_package_lifecycle.sh). Подключите `.stapler/update-check` и при необходимости `update-run`. Для приложения добавьте карточку и измените счётчик витрины. Для служебного пакета задайте `showcase = false`.

## Проверки

Из корня рабочей копии синхронизируйте метаданные и запустите общие проверки.

```bash
python3 .github/tools/sync_appstream.py
python3 .github/tools/sync_readme_versions.py
.github/tools/run_checks.sh
git diff --check
```

Проверьте изменённый пакет на p11. Здесь и далее `telegram` можно заменить другим именем пакета.

```bash
.github/tools/check_source_availability.sh telegram
stplr-spec verify-checksums --path telegram/Staplerfile
.github/tools/clean_build.sh telegram
.github/tools/verify_artifacts.sh telegram
NIVORA_LIFECYCLE_PACKAGES=telegram .github/tools/test_package_lifecycle.sh
```

По умолчанию для проверки обновления используется тестовый предыдущий RPM. Чтобы проверить переход с конкретной версии, положите старый RPM того же пакета и архитектуры в `.cache/previous-rpm/telegram.rpm` и повторите последнюю команду с `NIVORA_PREVIOUS_ARTIFACTS_DIR="$PWD/.cache/previous-rpm"`.

После проверки diff публикуйте обычным push в актуальный `main`. При изменении общих инструментов CI собирает весь каталог. [Расписание, ручная проверка и восстановление](.github/docs/maintenance.md)
