# Сопровождение Nivora

## Инварианты

- В репозитории ровно 21 каталог с `Staplerfile`.
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
| `distroshelf` | Upstream не публикует готовый Linux-релиз — Nivora CI собирает пакет из исходников и публикует результат в собственном GitHub Release, как и для `github-desktop`. См. раздел «Сборка в CI» ниже |
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

`stplr-spec` не публикуется в репозиториях дистрибутивов — CI собирает его из
исходников на закреплённом коммите (`.github/actions/setup-stplr-spec`). Для
локального запуска `verify-checksums`/`update-checksums`/`get-field` собрать
так же вручную:

```bash
git clone https://altlinux.space/stapler/stplr-utils.git
git -C stplr-utils checkout c6ddbb5e4e5637d97bb7b2587729178d715c6c52
GOBIN="$HOME/.local/bin" go install -C stplr-utils ./cmd/stplr-spec
```

Без `stplr-spec` в PATH `run_checks.sh` и `clean_build.sh` не падают —
соответствующие шаги (проверка полей Staplerfile, прогрев source-кэша)
молча пропускаются, а не сообщают об ошибке конфигурации. Сам `clean_build.sh`
всё равно соберёт пакет: прогрев кэша — это только ускорение, не обязательное
условие сборки.

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

## Сборка в CI (github-desktop, distroshelf)

Два пакета не переупаковывают готовый upstream-бинарник, а собираются
Nivora CI из исходников на отдельном workflow и публикуются в собственный
GitHub Release Nivora — `Staplerfile` только скачивает и переупаковывает
готовый результат, как и любой другой пакет.

`distroshelf`: upstream публикует только vendored source tarball (meson
dist со всеми Cargo-крейтами внутри, без обращения к crates.io на этапе
сборки), готового Linux-релиза нет вообще — основной канал upstream это
Flathub. `.github/workflows/distroshelf-linux.yml` собирает пакет внутри
официального контейнера `registry.altlinux.org/p11/base` — **не**
Sisyphus, Fedora или Ubuntu: у них более новый glibc, а собранный там
бинарник не запускается на системах со старым glibc (ALT p11 — glibc
2.38); собирать нужно на окружении с glibc не новее, чем у самой старой
поддерживаемой цели.

ALT p11 не публикует GTK4-флейвор VTE (`vte3-gtk4`) вообще, а системные
glib2/libadwaita младше версий, которые Cargo.toml DistroShelf запрашивает
по умолчанию (`gnome_49`/`v1_9`). Workflow:

1. собирает VTE 0.82.1 с `-Dgtk4=true` из исходников (закреплённый SHA-256
   архива `download.gnome.org`);
2. понижает фичи `gtk4`/`libadwaita` в Cargo.toml до `gnome_48`/`v1_8` —
   версий, реально доступных на ALT p11 (проверено вручную по исходникам:
   DistroShelf не вызывает API, специфичный для `gnome_49`/`v1_9`);
3. собирает DistroShelf офлайн (`-Doffline=true`, все Cargo-крейты уже в
   tarball) и встраивает собственную сборку `libvte-2.91-gtk4.so.0` в
   `/usr/lib/distroshelf/` вместе с wrapper-скриптом
   (`LD_LIBRARY_PATH=/usr/lib/distroshelf`), потому что системного пакета
   с этой библиотекой на ALT нет ни у кого;
4. публикует `tar.gz` в `github.com/Cheviiot/Nivora/releases/tag/distroshelf-<version>-linux`
   с `SHA256SUMS`, откуда `distroshelf/Staplerfile` его и скачивает.

`build_deps` у самого `distroshelf/Staplerfile` — минимальный (`binutils`,
как у `github-desktop`): весь тулчейн (`meson`, `rust`, dev-пакеты GTK4)
нужен только workflow, не конечному пользователю. `deps_altlinux`
перечисляет только прямые runtime-библиотеки (`libgtk4`, `libadwaita`,
`glib2`, `liblz4`) — `vte3-gtk4` туда не входит, потому что VTE-GTK4
bundled внутри пакета.

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
