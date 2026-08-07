# Сопровождение Nivora

## Инварианты

- В репозитории ровно 20 каталогов с `Staplerfile`.
- Каталог совпадает с `name` и командой в README.
- Инфраструктура (`tools/`, `docs/`, `tests/`) живёт внутри `.github/`, чтобы
  корень репозитория состоял только из каталогов пакетов и стандартных
  файлов (README, CHANGELOG, LICENSE и т.д.).
- Upstream-версия не меняется из-за патча рецепта; для этого повышается `release`.
- Desktop-id, AppStream component-id, units и пути данных не меняются без отдельной миграции.
- `provides` и `conflicts` остаются пустыми, а `replaces` содержит только собственное
  базовое имя пакета.

Stapler сам добавляет текущее `name` в generated `Provides` и `Conflicts`. Рецепты не
добавляют переходные package ID и не зависят от других Stapler-каталогов.

## Названия

| Package ID | Основание |
|:--|:--|
| `claude` | Upstream DEB: `Package: claude-desktop`; desktop-id `com.anthropic.Claude` сохранён; старое имя пакета `claude-desktop` заменяется |
| `codex` | Отображаемое имя `Codex`; команда и desktop-id `codex-app` сохранены |
| `distroshelf` | Единственный пакет, собираемый из исходников (meson+cargo), а не из готового upstream-бинарника — upstream не публикует прекомпилированный Linux-релиз, только vendored source tarball. См. раздел «Сборка из исходников» ниже |
| `github-desktop` | Официальный upstream `desktop/desktop`; Linux-сборка без стороннего форка |
| `nivora-cli` | Многоязычная оболочка Nivora для Stapler |
| `telegram` | Upstream-тарбол не даёт своего package ID; desktop-id `org.telegram.desktop` сохранён; каталог и package ID переименованы с `telegram-desktop`. В отличие от `claude`/`claude-desktop`, `replaces` не включает старое имя (это разрешено только для `claude` в `validate_repo.py`) — у кого установлен `telegram-desktop`, нужно вручную `stplr install telegram` и `stplr remove telegram-desktop` |
| `vesktop` | Пакет намеренно не называется `discord`: официальный `.deb`/`.tar.gz` Discord — самообновляющийся bootstrap без пригодного для SHA-256-пиннинга payload (см. `vesktop/README.md`). `vesktop` — реальный upstream package ID стороннего клиента Vencord, ставится как есть |

## Локальные проверки

```bash
.github/tools/run_checks.sh
.github/tools/package_updates.sh check-all
.github/tools/verify_artifacts.sh --all
.github/tools/test_package_lifecycle.sh
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

Полный жизненный цикл проверяется для пяти критичных пакетов. Остальные пакеты
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
.github/tools/run_checks.sh
.github/tools/clean_build.sh package
```

Нестандартная логика обнаружения версий находится в `.github/tools/package_updates.sh`, а каждый
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

## Сборка из исходников

Почти все пакеты Nivora переупаковывают готовый upstream-бинарник (`.deb`,
`.tar.xz`) без компиляции. `distroshelf` — исключение: upstream публикует
только vendored source tarball (meson dist со всеми Cargo-крейтами внутри,
без обращения к crates.io на этапе сборки), поэтому `package()` реально
выполняет `meson setup` + `meson compile` + `meson install
DESTDIR="${pkgdir}"` внутри clean-build контейнера.

Для такого пакета:

- `build_deps_altlinux` перечисляет полный тулчейн (`meson`, `ninja-build`,
  `rust`, `pkgconfig`, `gcc-c++`, dev-пакеты нужных библиотек) — без него
  `stplr build` не соберёт исходники;
- `deps_altlinux` содержит только прямые runtime-библиотеки (без
  `auto_reqprov_method="dirty"`/`auto_req=0` — те нужны только Electron-пакетам
  с bundled-библиотеками); транзитивные зависимости резолвит сам пакетный
  менеджер через `Requires` перечисленных пакетов;
- контрольная сумма фиксирует только сам source tarball — она не покрывает
  версии системных библиотек ALT, с которыми линкуется бинарник на этапе
  сборки, поэтому `clean-build` для этого пакета воспроизводим лишь в
  границах одного снапшота Sisyphus.

## Clean-build

```bash
.github/tools/clean_build.sh package
.github/tools/clean_build.sh --all
.github/tools/verify_artifacts.sh --all
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

Автоматизированная проверка выполняется командой `.github/tools/test_package_lifecycle.sh` в
одноразовых контейнерах, а не на рабочей системе сопровождающего.
