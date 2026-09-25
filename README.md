<p align="center">
  <img src=".github/assets/readme-hero.png" width="100%" alt="Nivora — независимый каталог приложений для ALT Linux и Stapler">
</p>

<p align="center">
  <a href="https://stplr.dev/docs/intro/"><img src="https://img.shields.io/badge/Stapler-v0.1.1-8b5cf6?style=flat-square" alt="Stapler v0.1.1"></a>
  <img src="https://img.shields.io/badge/packages-16-19bfc8?style=flat-square" alt="16 пакетов">
  <img src="https://img.shields.io/badge/ALT-p11%20%7C%20sisyphus-52d99b?style=flat-square" alt="ALT p11 и Sisyphus">
  <a href="https://github.com/Cheviiot/Nivora/actions/workflows/quality.yml"><img src="https://img.shields.io/github/actions/workflow/status/Cheviiot/Nivora/quality.yml?branch=main&amp;style=flat-square&amp;label=quality" alt="Статус CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-7188f5?style=flat-square" alt="MIT License"></a>
</p>

<p align="center">
  Готовые рецепты десктопных приложений и системных инструментов<br>
  для ALT Linux, которых нет в штатных репозиториях дистрибутива.
</p>

<p align="center">
  <a href="#-быстрый-старт">Быстрый старт</a> ·
  <a href="#-каталог">Каталог</a> ·
  <a href="#-совместимость">Совместимость</a> ·
  <a href="#-безопасность-и-доверие">Безопасность</a> ·
  <a href="CONTRIBUTING.md">Участие в проекте</a>
</p>

<!-- package-count -->
<p align="center"><strong>16 пакетов</strong> · <strong>4 категории</strong> · <code>ALT p11</code> и <code>ALT Sisyphus</code> · <code>amd64</code>, <code>arm64</code></p>

> [!NOTE]
> Nivora — независимый community-репозиторий. Он не является официальным
> репозиторием Stapler или официальным каналом распространения приложений.

## ✦ Почему Nivora

| Прозрачные рецепты | Проверяемые загрузки | Честная совместимость |
|:--|:--|:--|
| Каждый `Staplerfile` открыт для аудита: источники, зависимости, hooks и состав пакета видны до установки. | Загружаемые файлы закреплены SHA-256, изменяемые upstream-источники дополнительно контролируются fingerprint, а доступность каждого источника подтверждается до фиксации контрольной суммы. | Матрица различает доказанную, частичную и неподдерживаемую конфигурации по каждой паре «ветка ALT + архитектура», без завышенных обещаний. |

## ⚡ Быстрый старт

Нужен [Stapler](https://stplr.dev/docs/intro/) `v0.1.1` или новее.

```bash
# 1. Подключить Nivora
sudo stplr repo add nivora https://github.com/Cheviiot/Nivora.git

# 2. Загрузить индекс
sudo stplr refresh

# 3. Изучить и установить пакет
stplr info nivora/chatgpt
sudo stplr install nivora/chatgpt
```

Индекс обновляется только явной командой `sudo stplr refresh`. Nivora не
полагается на неработающий в Stapler v0.1.1 параметр `autoPull`.

Пять пакетов каталога — проприетарные (`chatgpt`, `claude`, `happ`, `parsec`,
`yandex-music`). Они объявлены как `nonfree`, поэтому при интерактивной
установке Stapler сначала показывает условия разработчика со ссылкой на
оригинальный документ и не продолжает без вашего согласия.

## ◈ Каталог

Нажмите на название приложения, чтобы открыть подробности. В строке пакета —
версия, архитектуры рецепта и идентификатор; ставится он командой
`sudo stplr install <идентификатор>`.

<!-- catalog:start -->
### Интернет, сеть и VPN

<table>
  <tr><!-- package-card:happ -->
    <td width="40" align="center"><img src="https://happ.su/imgs/apple-touch-icon.png" width="32" height="32" alt="Happ"></td>
    <td><a href="https://happ.su/"><strong>Happ</strong></a><br><sub>GUI-клиент xray-core и VPN</sub></td>
    <td align="right" nowrap><code>4.3.0</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/happ</code></td>
  </tr>
  <tr><!-- package-card:tailscale -->
    <td width="40" align="center"><img src="https://tailscale.com/favicon.png" width="32" height="32" alt="Tailscale"></td>
    <td><a href="https://tailscale.com/"><strong>Tailscale</strong></a><br><sub>Mesh VPN на базе WireGuard</sub></td>
    <td align="right" nowrap><code>1.102.4</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/tailscale</code></td>
  </tr>
  <tr><!-- package-card:telegram -->
    <td width="40" align="center"><img src="telegram/telegram-desktop.png" width="32" height="32" alt="Telegram"></td>
    <td><a href="https://desktop.telegram.org/"><strong>Telegram</strong></a><br><sub>Официальный мессенджер</sub></td>
    <td align="right" nowrap><code>7.2.5</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/telegram</code></td>
  </tr>
  <tr><!-- package-card:vesktop -->
    <td width="40" align="center"><img src="https://raw.githubusercontent.com/Vencord/Vesktop/main/build/icon.svg" width="32" height="32" alt="Vesktop"></td>
    <td><a href="vesktop/README.md"><strong>Vesktop</strong></a><br><sub>Discord-клиент с Vencord</sub></td>
    <td align="right" nowrap><code>1.6.7</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/vesktop</code></td>
  </tr>
</table>

### AI и разработка

<table>
  <tr><!-- package-card:chatgpt -->
    <td width="40" align="center"><img src="chatgpt/chatgpt.png" width="32" height="32" alt="ChatGPT"></td>
    <td><a href="chatgpt/README.md"><strong>ChatGPT</strong></a><br><sub>Десктопный клиент OpenAI</sub></td>
    <td align="right" nowrap><code>26.917.71314</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/chatgpt</code></td>
  </tr>
  <tr><!-- package-card:claude -->
    <td width="40" align="center"><img src="claude/claude-tray-orange.png" width="32" height="32" alt="Claude"></td>
    <td><a href="claude/README.md"><strong>Claude</strong></a><br><sub>Десктопный клиент Anthropic</sub></td>
    <td align="right" nowrap><code>2.7032.0</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/claude</code></td>
  </tr>
  <tr><!-- package-card:github-desktop -->
    <td width="40" align="center"><img src="https://github.githubassets.com/favicons/favicon.png" width="32" height="32" alt="GitHub Desktop"></td>
    <td><a href="github-desktop/README.md"><strong>GitHub Desktop</strong></a><br><sub>Официальный клиент GitHub</sub></td>
    <td align="right" nowrap><code>3.6.6</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/github-desktop</code></td>
  </tr>
  <tr><!-- package-card:vintner -->
    <td width="40" align="center"><img src=".github/assets/nivora.png" width="32" height="32" alt="Vintner"></td>
    <td><a href="https://github.com/Cheviiot/vintner"><strong>Vintner</strong></a><br><sub>MSVC на Linux через Wine</sub></td>
    <td align="right" nowrap><code>0.5.0</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/vintner</code></td>
  </tr>
</table>

### Медиа и игры

<table>
  <tr><!-- package-card:yandex-music -->
    <td width="40" align="center"><img src="yandex-music/yandex-music.png" width="32" height="32" alt="Yandex Music"></td>
    <td><a href="yandex-music/README.md"><strong>Yandex Music</strong></a><br><sub>Клиент Яндекс Музыки</sub></td>
    <td align="right" nowrap><code>5.121.2</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/yandex-music</code></td>
  </tr>
  <tr><!-- package-card:anidesk -->
    <td width="40" align="center"><img src="anidesk/anidesk.png" width="32" height="32" alt="AniDesk"></td>
    <td><a href="https://github.com/theDesConnet/AniDesk"><strong>AniDesk</strong></a><br><sub>Desktop-клиент Anixart</sub></td>
    <td align="right" nowrap><code>0.0.1-beta.7</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/anidesk</code></td>
  </tr>
  <tr><!-- package-card:pineconemc -->
    <td width="40" align="center"><img src="pineconemc/pineconemc.svg" width="32" height="32" alt="PineconeMC"></td>
    <td><a href="https://pineconemc.com/"><strong>PineconeMC</strong></a><br><sub>Minecraft-лаунчер с Ely.by</sub></td>
    <td align="right" nowrap><code>11.1.0</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/pineconemc</code></td>
  </tr>
  <tr><!-- package-card:parsec -->
    <td width="40" align="center"><img src="https://parsec.app/favicon.ico" width="32" height="32" alt="Parsec"></td>
    <td><a href="https://parsec.app/downloads"><strong>Parsec</strong></a><br><sub>Удалённый рабочий стол</sub></td>
    <td align="right" nowrap><code>150-104a</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/parsec</code></td>
  </tr>
</table>

### Системные инструменты

<table>
  <tr><!-- package-card:armbian-imager -->
    <td width="40" align="center"><img src="https://raw.githubusercontent.com/armbian/imager/main/public/armbian-icon.png" width="32" height="32" alt="Armbian Imager"></td>
    <td><a href="armbian-imager/README.md"><strong>Armbian Imager</strong></a><br><sub>Запись образов Armbian</sub></td>
    <td align="right" nowrap><code>2.0.4</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/armbian-imager</code></td>
  </tr>
  <tr><!-- package-card:balena-etcher -->
    <td width="40" align="center"><img src="https://raw.githubusercontent.com/balena-io/etcher/master/assets/icon.png" width="32" height="32" alt="balenaEtcher"></td>
    <td><a href="https://etcher.balena.io/"><strong>balenaEtcher</strong></a><br><sub>Запись образов на SD и USB</sub></td>
    <td align="right" nowrap><code>2.1.7</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/balena-etcher</code></td>
  </tr>
  <tr><!-- package-card:distroshelf -->
    <td width="40" align="center"><img src="https://raw.githubusercontent.com/ranfdev/DistroShelf/main/data/icons/hicolor/scalable/apps/com.ranfdev.DistroShelf.svg" width="32" height="32" alt="DistroShelf"></td>
    <td><a href="distroshelf/README.md"><strong>DistroShelf</strong></a><br><sub>Управление Distrobox</sub></td>
    <td align="right" nowrap><code>1.5.2</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/distroshelf</code></td>
  </tr>
  <tr><!-- package-card:ventoy -->
    <td width="40" align="center"><img src="https://raw.githubusercontent.com/ventoy/Ventoy/master/ICON/logo_128.png" width="32" height="32" alt="Ventoy"></td>
    <td><a href="ventoy/README.md"><strong>Ventoy</strong></a><br><sub>Мультизагрузочные USB</sub></td>
    <td align="right" nowrap><code>1.1.17</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/ventoy</code></td>
  </tr>
</table>
<!-- catalog:end -->

## ◎ Совместимость

Nivora — репозиторий **только для ALT Linux**. Поддерживаются две ветки:
`p11` и `Sisyphus`. Рецепты не содержат зависимостей других дистрибутивов, и
`compatible_with` каждого пакета ограничен `altlinux`.

Обязательный контракт — релизный Stapler `v0.1.1`; закреплённый commit `main`
проверяется как advisory canary для раннего обнаружения несовместимости.

| Уровень | Что означает |
|:--|:--|
| 🟢 `verified` | Сборка, metadata, установка, безопасный smoke и удаление выполняются блокирующими проверками в одноразовом контейнере этой ветки ALT. |
| 🔵 `partial` | Поддержка объявлена с явными ограничениями, ячейка не является блокирующей проверкой. |
| ⚫ `unsupported` | Цель исключается до сборки. |

У GitHub нет ALT-раннера, поэтому все проверки выполняются в официальных
контейнерах ALT на runner-е `x86_64`. Отсюда честная граница: `amd64` на обеих
ветках — `verified`, а `aarch64` объявлен, но **не проверяется в CI** и
собирается Stapler-ом на машине пользователя.

Точные цели и ограничения каждого пакета находятся в
[машиночитаемой матрице](.github/support-matrix.toml).

## ↻ Обновление

```bash
sudo stplr refresh
sudo stplr upgrade
```

Рецепты сохраняют пользовательские конфигурации. Обычное обновление или
удаление пакета не сбрасывает настройки и не завершает принудительно
пользовательскую сессию.

Для пакетов с системными службами (`tailscale`, `happ`) это уточнено явно:
служба включается **один раз**, при первой установке. Обновление не включает
её заново, если вы её отключили, но перезапускает уже работающую, чтобы вы не
остались на старом бинарнике. Пользовательские настройки вроде Tailscale
operator тоже назначаются только при первой установке.

## ◉ Безопасность и доверие

- Исходники рецептов и package hooks доступны для проверки до установки.
- SHA-256 подтверждает целостность выбранной загрузки, но сам по себе не делает upstream доверенным.
- Контрольная сумма фиксируется только после подтверждения, что источник действительно опубликован: Stapler v0.1.1 не проверяет HTTP-статус и иначе закрепил бы страницу ошибки как payload.
- Проприетарные приложения остаются под лицензиями и условиями их разработчиков.
- Проприетарные payload не публикуются в постоянных кэшах Nivora.
- Успешный CI не является обещанием абсолютной безопасности или совместимости с любой системой.

Подробнее: [модель доверия](.github/docs/security-model.md),
[политика безопасности](SECURITY.md) и [история изменений](CHANGELOG.md).

## Код и участие

Хотите добавить пакет или улучшить существующий рецепт — начните с
[руководства контрибьютора](CONTRIBUTING.md). Процесс обновления, локальные
проверки и правила сопровождения описаны в
[maintenance guide](.github/docs/maintenance.md).

<details>
<summary><strong>Команды сопровождающего</strong></summary>

```bash
.github/tools/run_checks.sh
.github/tools/package_updates.sh check-all
.github/tools/check_source_availability.sh <package>
NIVORA_ALT_BRANCH=sisyphus .github/tools/clean_build.sh --all
.github/tools/verify_artifacts.sh --all
NIVORA_ALT_BRANCH=sisyphus .github/tools/test_package_lifecycle.sh
```

</details>

---

<p align="center">
  <img src=".github/assets/nivora.png" width="54" height="54" alt="Nivora"><br>
  <strong>Nivora</strong> · Linux-пакеты без магии за кулисами<br>
  <sub>MIT © 2026 Cheviiot</sub>
</p>
