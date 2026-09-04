# Сопровождение Nivora

## Инварианты

- В репозитории ровно 16 каталогов с `Staplerfile`.
- Каталог совпадает с `name` и командой в README.
- Общая инфраструктура (`tools/`, `docs/`, интеграционные `tests/`) живёт внутри
  `.github/`; package-specific тесты и fixtures могут находиться рядом с
  соответствующим `Staplerfile`. Корень остаётся набором каталогов пакетов и
  стандартных файлов (README, CHANGELOG, LICENSE и т.д.).
- Upstream-версия не меняется из-за патча рецепта; для этого повышается `release`.
- Desktop-id, AppStream component-id, units и пути данных не меняются без отдельной миграции.
- `provides` и `conflicts` остаются пустыми, а `replaces` содержит собственное
  базовое имя пакета, кроме явно проверенных переходных package ID.

Stapler сам добавляет текущее `name` в generated `Provides` и `Conflicts`. Рецепты не
зависят от других Stapler-каталогов. Разрешённые переходы фиксирует validator:
`codex → chatgpt`, `claude-desktop → claude` и `telegram-desktop → telegram`.

## Уровни поддержки Stapler

| Lane | Pin | Роль | Результат |
|:--|:--|:--|:--|
| Stable | tag `v0.1.1`, commit `b5e293f6442f3cba1eeeea4b53c3c0e0bc2ae3e1` | минимальная пользовательская версия | обязательный, блокирующий |
| Main canary | commit `9df2b9284d3a37cdc418cef2e77781bac3b8dc3e` | ранняя проверка следующего Stapler | диагностический, не заменяет stable |

Pin canary меняется отдельным reviewable diff после изучения upstream. Рецепт
не может использовать функцию, существующую только в canary. Падение stable
блокирует выпуск; падение canary создаёт задачу совместимости, но не заставляет
переключать пользователей с release на development build.

Для всех изменённых пакетов stable и canary собирают RPM в ALT Sisyphus на
`x86_64`/`noarch`. Дополнительно `package-ci.yml` всегда получает blocking native
lifecycle-план из `support-matrix.toml`. Сейчас он содержит две доказанные ячейки:
`nivora-cli` на Ubuntu 24.04 `amd64` и `arm64`. ARM-бинарник Stapler собирается
именно из commit релиза `v0.1.1`, потому что upstream не публикует ARM-архив.
Уровень `verified` запрещён validator-ом без native runner и обязательной
build/install/smoke/remove ячейки; остальные дистрибутивы остаются `partial` или
`experimental`, а не выдаются за проверенные.

Индекс репозиториев обновляется явным `stplr refresh`. Ни автоматизация, ни
Nivora CLI не считают `autoPull` достаточным или гарантированным: после `repo add`,
изменения ref и перед диагностикой воспроизводимости refresh вызывается отдельным
видимым шагом.

## Названия

| Package ID | Основание |
|:--|:--|
| `chatgpt` | Официальный upstream `Package: chatgpt`; переходные `provides/replaces/conflicts` заменяют прежний package ID `codex` |
| `claude` | Upstream DEB: `Package: claude-desktop`; desktop-id `com.anthropic.Claude` сохранён; старое имя пакета `claude-desktop` заменяется |
| `distroshelf` | Upstream не публикует готовый Linux-релиз — Nivora CI собирает пакет из исходников и публикует результат в собственном GitHub Release, как и для `github-desktop`. См. раздел «Сборка в CI» ниже |
| `github-desktop` | Официальный upstream `desktop/desktop`; Linux-сборка без стороннего форка |
| `nivora-cli` | Многоязычная оболочка Nivora для Stapler |
| `telegram` | Upstream-тарбол не даёт своего package ID; desktop-id `org.telegram.desktop` сохранён; переходные metadata заменяют прежний package ID `telegram-desktop` |
| `vesktop` | Пакет намеренно не называется `discord`: официальный `.deb`/`.tar.gz` Discord — самообновляющийся bootstrap без пригодного для SHA-256-пиннинга payload (см. `vesktop/README.md`). `vesktop` — реальный upstream package ID стороннего клиента Vencord, ставится как есть |

## Зависимости на ALT

`deps_altlinux`/`opt_deps_altlinux` не поддерживают запись альтернатив
(«один из нескольких пакетов»), даже когда синтаксис для этого формально
есть. Проверено установкой настоящего RPM (не просто чтением
Staplerfile), оба варианта дают одинаковую ошибку:

- debian-style `'a | b'` — `apt-get install <local.rpm>` на ALT видит
  буквальную строку с `|` как единое имя пакета и валит установку;
- настоящий RPM rich-dependency `'(a or b)'` — та же ошибка, apt-rpm ALT
  не разбирает альтернативы в `Requires` локального пакета вообще.

Единственный рабочий вариант в каждом поле ALT-зависимостей — конкретное имя
пакета. Если оно отличается между ветками ALT, Stapler `v0.1.1` передаёт
`ALT_BRANCH_ID` и применяет более точные поля `deps_altlinux_p11` и
`deps_altlinux_sisyphus`. Так `parsec` выбирает `libavcodec61` для p11 и
`libavcodec62` для Sisyphus без неработающих альтернатив в одном `Requires`.

`opt_deps_altlinux` с `|` — не той же природы: `opt_deps` вообще не
попадают в `Recommends`/`Suggests` собранного RPM, это информационное
поле, поэтому там альтернативы синтаксически «работают» просто потому что
ни на что не влияют.

## Локальные проверки

На ALT Workstation dev-only инструменты запускаются в Distrobox. Согласованное
имя окружения и базовый setup:

```bash
distrobox create --name nivora-dev \
  --image registry.altlinux.org/alt/alt:sisyphus
distrobox enter nivora-dev
sudo apt-get update
sudo apt-get install git-core bash python3 shellcheck curl
```

Не устанавливайте toolchain или distro-specific build dependencies на host.
Проектные Go/Python-зависимости должны оставаться в рабочей копии или контейнере.

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

`stplr-spec` обязателен: без него `run_checks.sh`, `clean_build.sh` и
`verify_artifacts.sh` завершаются с ошибкой конфигурации. Это не позволяет
локальному или CI-запуску молча пропустить семантическую проверку рецептов.

`run_checks.sh` выполняет `bash -n`, ShellCheck, Python compile, unit-тесты, validator и чтение
всех `Staplerfile` через `stplr-spec`.

Если рецепт задаёт `appstream_app_id`, рядом со `Staplerfile` обязательно лежит
`<appstream_app_id>.metainfo.xml`. Это не source для payload: Stapler v0.1.1
читает sidecar при индексации репозитория и обогащает им `info` и поиск.
Validator разбирает XML и сверяет component ID с desktop launchable, поэтому
повреждённый или забытый sidecar не игнорируется молча.

Локальные URL уникальны между пакетами (например,
`local:///LICENSE?nivora=chatgpt`). В Stapler v0.1.1 ключ local-cache основан на
полном URL; уникальный query предотвращает гонку hardlink-cache, когда
параллельные сборки разных рецептов используют одно имя `LICENSE`.

`verify_artifacts.sh` сопоставляет готовые RPM с `files()`, проверяет владельцев путей,
права, desktop-файлы, systemd units, иконки, лицензии и метаданные совместимости.

`test_package_lifecycle.sh` собирает настоящие DEB текущей версии и использует настоящие
RPM из clean-build. По умолчанию минимальные транзакционные fixtures изображают
предыдущую версию того же package ID; это не выдаётся за runtime старого payload.
При наличии `NIVORA_PREVIOUS_ARTIFACTS_DIR` тест вместо fixtures использует реальные
предыдущие артефакты, названные `<package>.deb` и `<package>.rpm`; файл обязателен
только для формата, который пакет реально поддерживает.
Каждая поддерживаемая пара package/format проверяется в отдельном одноразовом Ubuntu или ALT-контейнере,
чтобы зависимости ранее проверенного пакета не могли скрыть неполный список текущего.
Через нативный пакетный менеджер проверяются:

1. обновление с предыдущей версии Nivora на текущую;
2. `Provides`, `Replaces` и `Conflicts`;
3. наличие команды, desktop-файла или systemd unit;
4. сохранение пользовательского состояния после обновления и удаления.

Транзакционный install/upgrade/remove smoke выполняется для всех 16 активных пакетов.
Полноценное обновление с ранее опубликованного payload проверяется только при передаче
реальных артефактов через `NIVORA_PREVIOUS_ARTIFACTS_DIR`.
Для точечной перепроверки после обновления можно передать разделённый запятыми список,
например `NIVORA_LIFECYCLE_PACKAGES=github-desktop`; неизвестные и повторяющиеся package ID
отклоняются до сборки.

Локально DEB собираются в привилегированном контейнере. На GitHub-hosted runner используется
`NIVORA_DEB_BUILD_MODE=host`: закреплённый stplr запускается непосредственно на одноразовом
Ubuntu runner, потому что вложенный sandbox stplr запрещён внутри Docker. Ubuntu 24.04 может
дополнительно блокировать непривилегированные user namespaces через AppArmor: тест временно
снимает только это ограничение, проверяет полный набор namespaces перед сборкой и
восстанавливает исходное значение при завершении. Для совместимости с моделью привилегий
Stapler временный builder включается в группу `wheel`, отсутствующую в Ubuntu по умолчанию.
Транзакционные сценарии в обоих режимах остаются изолированными в контейнерах.

На ALT Workstation полный локальный DEB/RPM lifecycle воспроизводимо проверен из
существующего Distrobox `ubuntu-dev`. Нужные distro-specific инструменты остаются
внутри контейнера, а Podman вызывается на host через Distrobox:

```bash
distrobox enter ubuntu-dev
sudo apt-get update
sudo apt-get install rpm sqlite3
podman() { distrobox-host-exec podman "$@"; }
export -f podman
.github/tools/test_package_lifecycle.sh
```

## Обновление пакета

```bash
stplr-spec update-package package
stplr-spec verify-checksums --path package/Staplerfile
.github/tools/run_checks.sh
.github/tools/clean_build.sh package
```

Нестандартная логика обнаружения версий находится в `.github/tools/package_updates.sh`, а каждый
`.stapler/update-check` вызывает его для своего package ID.

У ChatGPT и Parsec URL источника изменяемый (`latest`/без версии). Для них рецепт
хранит SHA-256 от HTTP ETag в `source_fingerprint*`. Detect-job дважды получает
fingerprint вокруг определения версии и формирует подписанный своим контекстом
план только при неизменном snapshot. Изолированная update-job сверяет этот exact
fingerprint до и после загрузки, а publish-validator принимает только значения
из detect-плана. Поэтому замена payload без смены версии обновляет checksum,
повышает `release` и не может быть ошибочно помечена как уже обработанная.

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

Служебный issue распознаётся только по точному заголовку, первой строке-marker и
автору `github-actions[bot]`. Диагностика ограничена по размеру и выводится как
код с нейтрализованными mentions/markers; пользовательский issue или upstream-log
не могут перехватить автоматическое обновление или закрытие отчёта.

Сбой post-push gate ставит updater на паузу, если проверявшийся SHA остаётся
предком текущего `main`; в pause-state записывается именно актуальная вершина,
чтобы параллельный последующий push не потерял ошибку. Для восстановления запускают
`post-push-verify.yml` на текущем потомке pause SHA с `resume_on_success=true`: workflow намеренно
проверяет все 16 пакетов, а не только последний diff, и лишь затем снимает паузу.

Прямой push — принятая модель проекта. Updater не создаёт pull request и не
подписывает commit или tag, поэтому перед push обязательны checksum, validator и
package-level build. Пользовательский корень доверия остаётся TOFU к GitHub URL,
аккаунту владельца и первой полученной истории. Workflow не должен переписывать
историю, отключать защитные проверки или публиковать изменение, если обязательный
stable lane не прошёл.

Updater обновляет только рецепт и связанные открытые metadata/assets. Он не
загружает проприетарный upstream payload в Nivora Releases или постоянные CI
artifacts. Временная загрузка допускается для checksum/сборки в одноразовом
workspace и должна исчезнуть вместе с job.

## Обходы дефектов Stapler

Каждый локальный workaround оформляется как ограниченная совместимость, а не как
новая семантика Nivora. Запись должна содержать:

1. ссылку на upstream issue или pull request;
2. минимальный воспроизводящий тест и ожидаемый результат;
3. затронутые release/commit Stapler;
4. локальный обход и оценку его безопасности;
5. release, после которого обход можно удалить.

Upstream pull request разрешён и предпочтителен для исправления общей проблемы,
но его merge недостаточен для удаления обхода. Удаление выполняется только когда
исправление вошло в новый поддерживаемый stable release, этот release и pinned
main прошли соответствующий минимальный тест, а Nivora больше не зависит от
старого поведения. До этого workaround остаётся узким, покрытым тестом и не
копируется в несвязанные recipes.

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
