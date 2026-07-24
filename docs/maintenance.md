# Сопровождение Nivora

## Инварианты

- В репозитории ровно 19 каталогов с `Staplerfile`.
- Каталог совпадает с `name` и командой в README.
- Upstream-версия не меняется из-за патча рецепта; для этого повышается `release`.
- Desktop-id, AppStream component-id, units и пути данных не меняются без отдельной миграции.
- `provides` и `conflicts` остаются пустыми, а `replaces` содержит только собственное
  базовое имя пакета.

Stapler сам добавляет текущее `name` в generated `Provides` и `Conflicts`. Рецепты не
добавляют переходные package ID и не зависят от других Stapler-каталогов.

## Названия

| Package ID | Основание |
|:--|:--|
| `clash-verge-rev` | Upstream-репозиторий и release title: Clash Verge Rev |
| `claude-desktop` | Upstream DEB: `Package: claude-desktop`; desktop-id `com.anthropic.Claude` сохранён |
| `codex` | Отображаемое имя `Codex`; команда и desktop-id `codex-app` сохранены |
| `github-desktop` | Официальный upstream `desktop/desktop`; Linux-сборка без стороннего форка |
| `nivora-stplr` | Собственный helper Nivora |

## Локальные проверки

```bash
tools/run_checks.sh
tools/package_updates.sh check-all
tools/verify_artifacts.sh --all
tools/test_package_lifecycle.sh
```

`run_checks.sh` выполняет `bash -n`, ShellCheck, Python compile, unit-тесты, validator и чтение
всех `Staplerfile` через `stplr-spec`.

`verify_artifacts.sh` сопоставляет готовые RPM с `files()`, проверяет владельцев путей,
права, desktop-файлы, systemd units, иконки, лицензии и метаданные совместимости.

`test_package_lifecycle.sh` собирает настоящие DEB текущей версии и использует настоящие
RPM из clean-build. Минимальные fixtures изображают предыдущую версию того же пакета Nivora.
В одноразовых Ubuntu и ALT-контейнерах через APT проверяются:

1. обновление с предыдущей версии Nivora на текущую;
2. `Provides`, `Replaces` и `Conflicts`;
3. наличие команды, desktop-файла или systemd unit;
4. сохранение пользовательского состояния после обновления и удаления.

Полный жизненный цикл проверяется для восьми критичных пакетов. Остальные пакеты
покрываются validator, clean-build и проверкой payload.

Локально DEB собираются в привилегированном контейнере. На GitHub-hosted runner используется
`NIVORA_DEB_BUILD_MODE=host`: закреплённый stplr запускается непосредственно на одноразовом
Ubuntu runner, потому что вложенный sandbox stplr запрещён внутри Docker. Ubuntu 24.04 может
дополнительно блокировать непривилегированные user namespaces через AppArmor: тест временно
снимает только это ограничение, проверяет полный набор namespaces перед сборкой и
восстанавливает исходное значение при завершении. Для совместимости с моделью привилегий
Stapler временный builder включается в группу `wheel`, отсутствующую в Ubuntu по умолчанию.
Транзакционные сценарии в обоих режимах остаются изолированными в контейнерах.

## Обновление пакета

```bash
stplr-spec update-package package
stplr-spec verify-checksums --path package/Staplerfile
tools/run_checks.sh
tools/clean_build.sh package
```

Нестандартная логика обнаружения версий находится в `tools/package_updates.sh`, а каждый
`.stapler/update-check` вызывает его для своего package ID.

Плановый workflow обновляет пакеты автономно и отправляет проверенные изменения
прямо в `main`. Он запускается ежедневно в 03:00 по Владивостоку
(`17:00 UTC`). Каждый пакет обрабатывается в отдельном временном worktree, поэтому
несовместимое обновление одного upstream не блокирует остальные. При сбое workflow
сохраняет на 30 дней диагностический artifact с полным логом, фазой сбоя, diff и
получившимся `Staplerfile`; успешно собранные пакеты всё равно публикуются. Для
каждого несовместимого пакета создаётся один постоянный issue: повторные сбои
обновляют его, а успешное восстановление автоматически закрывает. Ожидаемый сбой
отдельного пакета помечается предупреждением и не делает весь этап обновления
неуспешным.

## Clean-build

```bash
tools/clean_build.sh package
tools/clean_build.sh --all
tools/verify_artifacts.sh --all
```

Скрипт всегда выполняет сборку в собственном одноразовом контейнере ALT и не
подключает сторонние Stapler-каталоги.

## Проверка жизненного цикла

Для каждого критичного пакета нужно:

1. Собрать fixture предыдущей версии и текущий RPM/DEB.
2. Создать тестовый файл в каталоге данных.
3. Обновить пакет до текущей версии.
4. Проверить `Provides/Replaces/Conflicts`, payload и тестовый файл.
5. Проверить удаление пакета без удаления пользовательского состояния.

Автоматизированная проверка выполняется командой `tools/test_package_lifecycle.sh` в
одноразовых контейнерах, а не на рабочей системе сопровождающего.
