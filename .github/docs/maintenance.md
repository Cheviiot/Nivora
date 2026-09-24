# Сопровождение Nivora

## Инварианты

- Nivora — репозиторий **только для ALT Linux**. Поддерживаются ветки `p11` и
  `Sisyphus`; `compatible_with` каждого рецепта равен `('altlinux')`.
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

## Зависимости: одна цель, один список

Поскольку ALT — единственная цель, зависимости живут в базовых полях
`deps`, `opt_deps` и `build_deps`. Полей `deps_debian`, `deps_ubuntu`,
`deps_fedora`, `deps_arch`, `deps_opensuse` и `deps_alpine` в репозитории
больше нет, и validator их отвергает.

Ветку уточняют только там, где имя пакета реально различается. Stapler
резолвит overrides в порядке

```
deps_<arch>_altlinux_<branch> → deps_altlinux_<branch> →
deps_<arch>_altlinux → deps_altlinux → deps_<arch> → deps
```

и берёт **первое** совпадение целиком — override не дополняет базовый список,
а заменяет его. Поэтому `parsec` объявляет полный набор в обеих ветках:

```bash
deps=('glibc' 'libgcc1' ... 'libvulkan1')
deps_altlinux_p11=("${deps[@]}" 'libavcodec61')
deps_altlinux_sisyphus=("${deps[@]}" 'libavcodec62')
```

`ALT_BRANCH_ID` из `/etc/os-release` даёт `p11`/`sisyphus`, это и есть
`ReleaseID` в терминах Stapler.

`deps_altlinux` без ветки validator отклоняет: это ровно то же самое, что
базовый `deps`, только менее очевидно.

### Альтернативы запрещены

ALT `apt-rpm` не разбирает альтернативы в зависимости ни в каком виде.
Проверено установкой настоящего RPM, а не чтением рецепта:

- debian-style `'a | b'` — apt видит буквальную строку с `|` как одно имя
  пакета и валит установку;
- RPM rich-dependency `'(a or b)'` — та же ошибка.

Validator запрещает оба варианта во всех полях зависимостей, включая
`opt_deps`, где раньше они «работали» просто потому, что `opt_deps` вообще не
попадают в собранный RPM.

### auto_req и auto_reqprov_method

`auto_reqprov_method='dirty'` обязателен, `auto_prov=0` обязателен.

Это не произвол. У Stapler есть родной ALT-финдер (`auto_reqprov_method='rpm'`
→ `/usr/lib/rpm/find-requires`), который выдаёт честные ALT-зависимости с
set-версиями символов. Но каталог состоит в основном из self-contained
Electron- и Qt-пакетов, которые несут свои `libEGL.so.1`, `libGLESv2.so.1` и
прочее. Родной финдер сгенерирует на них `Requires`, удовлетворить которые
можно только включив `find-provides`, — а тогда пакет начнёт объявлять
bundled-библиотеки на всю систему. `dirty` вместо этого вычитает из набора
`DT_NEEDED` все `DT_SONAME`, которые пакет предоставляет сам
(`pkg/reqprov/dirty/dirty.go`, `diffSets`), и это единственная комбинация,
которая даёт корректные requires при выключенном `auto_prov`.

Побочные детали `dirty`, о которых стоит помнить:

- обрабатываются только исполняемые файлы и файлы вида `lib*.so*`
  (`looksLikeLib`), поэтому, например, `shared/lib/gbm/dri_gbm.so` у
  `pineconemc` в расчёт не попадает;
- `auto_req_filter` у ALT-финдера игнорируется целиком, а `auto_req_skiplist`
  работает; у `dirty` работают оба.

`auto_req=0` оставлен там, где список зависимостей полностью явный:
`parsec`, `tailscale`, `ventoy`, `vintner`.

### Как перепроверить зависимости

Имена пакетов сверяются с обеими ветками:

```bash
apt-cache policy <имя>                      # p11, если host — ALT p11
podman run --rm registry.altlinux.org/sisyphus/base \
  bash -c 'apt-get update -qq && apt-cache policy <имя>'
```

SONAME из payload сверяются через `Reverse Provides`:

```bash
apt-cache showpkg 'libgtk-3.so.0()(64bit)'
```

Последняя полная сверка: все объявленные имена зависимостей резолвятся в своей
ветке, все SONAME, которые `dirty` реально превращает в `Requires`,
предоставляются пакетами ALT в обеих ветках.

## Уровни поддержки Stapler

| Lane | Pin | Роль | Результат |
|:--|:--|:--|:--|
| Stable | tag `v0.1.1`, commit `b5e293f6442f3cba1eeeea4b53c3c0e0bc2ae3e1` | минимальная пользовательская версия | обязательный, блокирующий |
| Main canary | commit `9df2b9284d3a37cdc418cef2e77781bac3b8dc3e` | ранняя проверка следующего Stapler | диагностический, не заменяет stable |

Pin canary меняется отдельным reviewable diff после изучения upstream. Рецепт
не может использовать функцию, существующую только в canary. Падение stable
блокирует выпуск; падение canary создаёт задачу совместимости, но не заставляет
переключать пользователей с release на development build.

Для каждого изменённого пакета `package-ci.yml` собирает RPM и прогоняет
install/smoke/remove **в обеих ветках ALT** на `x86_64`. Canary собирает тот же
пакет на pinned `main` только в Sisyphus и остаётся advisory.

У GitHub нет ALT-раннера, поэтому «нативной» ячейки не существует в принципе:
все проверки идут в официальных контейнерах ALT. `verified` означает именно
это — блокирующие build/metadata/install/smoke/remove в одноразовом контейнере
нужной ветки. `aarch64` объявлен в рецептах, но в CI не проверяется и помечен
`partial` с caveat `arm64-not-gated`.

Индекс репозиториев обновляется явным `stplr refresh`. Ни автоматизация, ни
рецепты не считают `autoPull` достаточным или гарантированным.

## Названия

| Package ID | Основание |
|:--|:--|
| `chatgpt` | Официальный upstream `Package: chatgpt`; переходные `provides/replaces/conflicts` заменяют прежний package ID `codex` |
| `claude` | Upstream DEB: `Package: claude-desktop`; desktop-id `com.anthropic.Claude` сохранён; старое имя пакета `claude-desktop` заменяется |
| `distroshelf` | Upstream не публикует готовый Linux-релиз — Nivora CI собирает пакет из исходников и публикует результат в собственном GitHub Release, как и для `github-desktop`. См. раздел «Сборка в CI» ниже |
| `github-desktop` | Официальный upstream `desktop/desktop`; Linux-сборка без стороннего форка |
| `telegram` | Upstream-тарбол не даёт своего package ID; desktop-id `org.telegram.desktop` сохранён; переходные metadata заменяют прежний package ID `telegram-desktop` |
| `vesktop` | Пакет намеренно не называется `discord`: официальный `.deb`/`.tar.gz` Discord — самообновляющийся bootstrap без пригодного для SHA-256-пиннинга payload (см. `vesktop/README.md`). `vesktop` — реальный upstream package ID стороннего клиента Vencord, ставится как есть |

## Lifecycle-хуки

Stapler v0.1.1 прокидывает `preupgrade`/`postupgrade` **только** в
`info.ArchLinux.Scripts` и `info.APK.Scripts`
(`internal/scripter/utils.go`). Для RPM и DEB они молча игнорируются.
Соответственно:

- объявлять `postupgrade` бессмысленно — validator этого не требует, а тест
  ChatGPT прямо запрещает;
- `postinstall` отображается в RPM `%post`, который выполняется и при
  установке, и при обновлении;
- `$1` в `%post` — число установленных экземпляров: `1` при первой установке,
  `2` и больше при обновлении. В `%preun` `0` — удаление, `1` — обновление.

Отсюда правило для сервисных пакетов (`tailscale`, `happ`): `enable --now`
только при первой установке, `try-restart` при обновлении. Иначе обновление
заново включает юнит, который пользователь отключил, и при этом не
перезапускает уже работающий демон — он продолжает крутить старый бинарник.
Пользовательские настройки (например, Tailscale operator) назначаются один раз
при первой установке.

`postremove` различает удаление и обновление по наличию unit-файла: в
`%postun` при обновлении новый пакет уже вернул файл на место.

## Локальные проверки

На ALT Workstation dev-only инструменты запускаются в Distrobox:

```bash
distrobox create --name nivora-dev \
  --image registry.altlinux.org/alt/alt:sisyphus
distrobox enter nivora-dev
sudo apt-get update
sudo apt-get install git-core bash python3 shellcheck curl sqlite3 rpm-build
```

Не устанавливайте toolchain или distro-specific build dependencies на host.

```bash
.github/tools/run_checks.sh
.github/tools/package_updates.sh check-all
.github/tools/check_source_availability.sh <package> [version]
NIVORA_ALT_BRANCH=sisyphus .github/tools/clean_build.sh --all
.github/tools/verify_artifacts.sh --all
NIVORA_ALT_BRANCH=p11 .github/tools/test_package_lifecycle.sh
```

`NIVORA_ALT_BRANCH` (`p11` или `sisyphus`, по умолчанию `sisyphus`) выбирает
ветку для `clean_build.sh` и `test_package_lifecycle.sh`. Образ каждой ветки
закреплён по digest в `.github/support-matrix.toml`, общий резолвер —
`.github/tools/lib/alt_branch.sh`.

`stplr-spec` не публикуется в репозиториях дистрибутивов — CI собирает его из
исходников на закреплённом коммите (`.github/actions/setup-stplr-spec`). Для
локального запуска собрать так же вручную:

```bash
git clone https://altlinux.space/stapler/stplr-utils.git
git -C stplr-utils checkout c6ddbb5e4e5637d97bb7b2587729178d715c6c52
GOBIN="$HOME/.local/bin" go install -C stplr-utils ./cmd/stplr-spec
```

`stplr-spec` обязателен: без него `run_checks.sh`, `clean_build.sh` и
`verify_artifacts.sh` завершаются с ошибкой конфигурации. Это не позволяет
локальному или CI-запуску молча пропустить семантическую проверку рецептов.

`run_checks.sh` выполняет `bash -n`, ShellCheck, Python compile, unit-тесты,
validator и чтение всех `Staplerfile` через `stplr-spec`.

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

`test_package_lifecycle.sh` использует настоящие RPM из clean-build. По
умолчанию минимальные транзакционные fixtures изображают предыдущую версию
того же package ID; это не выдаётся за runtime старого payload. При наличии
`NIVORA_PREVIOUS_ARTIFACTS_DIR` тест вместо fixtures использует реальные
предыдущие артефакты, названные `<package>.rpm`. Каждый пакет проверяется в
отдельном одноразовом контейнере ALT, чтобы зависимости ранее проверенного
пакета не могли скрыть неполный список текущего. Проверяются:

1. обновление с предыдущей версии Nivora на текущую;
2. `Provides`, `Replaces` и `Conflicts`;
3. наличие команды, desktop-файла или systemd unit;
4. права `4755` у Electron `chrome-sandbox`, где он есть;
5. сохранение пользовательского состояния после обновления и удаления.

Для точечной перепроверки можно передать разделённый запятыми список,
например `NIVORA_LIFECYCLE_PACKAGES=github-desktop`; неизвестные и
повторяющиеся package ID отклоняются до сборки.

## Обновление пакета

```bash
.github/tools/check_source_availability.sh package <новая-версия>
stplr-spec update-package package
stplr-spec verify-checksums --path package/Staplerfile
.github/tools/run_checks.sh
NIVORA_ALT_BRANCH=sisyphus .github/tools/clean_build.sh package
```

Нестандартная логика обнаружения версий находится в
`.github/tools/package_updates.sh`, а каждый `.stapler/update-check` вызывает
его для своего package ID.

### Источник версии обязан совпадать с источником загрузки

Stapler v0.1.1 **не проверяет HTTP-статус вообще**: `pkg/dl/file.go` отдаёт
`res.Body` в запись, не глядя на код ответа, поэтому страница 404 сохраняется
как source, а `stplr-spec update-checksums` спокойно пинит её SHA-256. Рецепт
после этого выглядит валидным и падает только на сборке — и то лишь если
`package()` распаковывает payload.

Поэтому:

- `.github/tools/check_source_availability.sh` — обязательная фаза
  `check-sources` автообновления. Она рендерит все массивы `sources*` для
  планируемой версии, снимает `~name`/`~archive` ровно как
  `FileDownloader.parseURLAndParams`, и требует 2xx и ненулевого размера до
  того, как checksum будет зафиксирован;
- детектор версии обязан спрашивать тот же хост, с которого идёт загрузка.
  `telegram` — показательный случай: GitHub-тег `telegramdesktop/tdesktop`
  появляется раньше, чем `td.telegram.org/tlinux/tsetup.<version>.tar.xz`,
  поэтому `latest_telegram` подтверждает наличие тарбола и иначе остаётся на
  текущей версии.

### Изменяемые источники

У ChatGPT и Parsec URL источника изменяемый (`latest`/без версии). Для них рецепт
хранит SHA-256 от HTTP ETag в `source_fingerprint*`. Detect-job дважды получает
fingerprint вокруг определения версии и формирует подписанный своим контекстом
план только при неизменном snapshot. Изолированная update-job сверяет этот exact
fingerprint до и после загрузки, а publish-validator принимает только значения
из detect-плана. Поэтому замена payload без смены версии обновляет checksum,
повышает `release` и не может быть ошибочно помечена как уже обработанная.
У ChatGPT fingerprint также входит в служебный query-параметр `nivora` каждого
source URL. Это меняет ключ локального кэша Stapler вместе с payload и не даёт
старому файлу из `/latest/` вызвать checksum mismatch у пользователя. Параметр
не удалять при обновлении рецепта.

### Автономный workflow

Плановый workflow обновляет пакеты автономно и отправляет проверенные изменения
прямо в `main`. Он запускается на 17-й минуте каждого часа
(`17 * * * *` в UTC). Каждый пакет обрабатывается в отдельном временном worktree, поэтому
несовместимое обновление одного upstream не блокирует остальные. При сбое workflow
сохраняет на 30 дней диагностический artifact с полным логом, фазой сбоя, diff и
получившимся `Staplerfile`; успешно собранные пакеты всё равно публикуются. Для
каждого несовместимого пакета создаётся один постоянный issue: повторные сбои
обновляют его, а успешное восстановление автоматически закрывает.

Фазы: `detect-version`, `prepare-worktree`, `check-sources`, `update-recipe`,
`pin-upstream-commit`, `pin-source-fingerprint`, `sync-catalog`,
`static-checks`, `clean-build`, `verify-artifact`.

**Патч ограничен каталогом пакета**, и publish-gate принимает ровно один
изменённый путь. Из этого следует правило: никакой общий файл не может
требовать синхронного изменения вместе с версией пакета. Раньше этого правила
не было, и `github-desktop` оказался неспособен обновиться в принципе — в
`github-desktop-linux.yml` был захардкожен `3.6.5`, а validator требовал
совпадения с рецептом. Версия теперь приходит только через обязательный вход
`version`, а validator, наоборот, запрещает любой литерал версии в этом
workflow.

Служебный issue распознаётся только по точному заголовку, первой строке-marker и
автору `github-actions[bot]`. Диагностика ограничена по размеру и выводится как
код с нейтрализованными mentions/markers; пользовательский issue или upstream-log
не могут перехватить автоматическое обновление или закрытие отчёта.

Сбой post-push gate ставит updater на паузу, если проверявшийся SHA остаётся
предком текущего `main`; в pause-state записывается именно актуальная вершина,
чтобы параллельный последующий push не потерял ошибку. Для восстановления запускают
`post-push-verify.yml` на текущем потомке pause SHA с `resume_on_success=true`: workflow
намеренно проверяет все пакеты, а не только последний diff, и лишь затем снимает паузу.

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
старого поведения.

Известные дефекты Stapler v0.1.1, на которые опирается инфраструктура:

| Дефект | Файл | Обход |
|:--|:--|:--|
| HTTP-статус не проверяется при загрузке source | `pkg/dl/file.go` | `check_source_availability.sh` как фаза `check-sources` |
| `preupgrade`/`postupgrade` игнорируются для RPM и DEB | `internal/scripter/utils.go` | хуки различают установку и обновление по `$1` в `%post` |
| `auto_req_filter` игнорируется ALT-финдером | `pkg/reqprov/rpm/altlinux.go` | используется `dirty` + `auto_req_skiplist` |

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
Sisyphus: у Sisyphus более новый glibc, а собранный там бинарник не
запускается на p11 (glibc 2.38). Собирать нужно на окружении с glibc не
новее, чем у самой старой поддерживаемой цели.

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
нужен только workflow, не конечному пользователю. `deps`
перечисляет только прямые runtime-библиотеки — `vte3-gtk4` туда не входит,
потому что VTE-GTK4 bundled внутри пакета.

## Clean-build

```bash
NIVORA_ALT_BRANCH=sisyphus .github/tools/clean_build.sh package
NIVORA_ALT_BRANCH=p11 .github/tools/clean_build.sh --all
.github/tools/verify_artifacts.sh --all
```

Скрипт всегда выполняет сборку в собственном одноразовом контейнере ALT и не
подключает сторонние Stapler-каталоги.
