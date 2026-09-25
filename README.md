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
<p align="center"><strong>16 пакетов</strong> · <strong>6 категорий</strong> · <code>ALT p11</code> и <code>ALT Sisyphus</code> · <code>amd64</code>, <code>arm64</code></p>

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

Нажмите на название приложения, чтобы открыть подробности. Рядом с версией
указаны архитектуры, которые объявляет рецепт.

<!-- catalog:start -->
### Интернет, сеть и VPN

<table>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:happ -->
      <img src="https://happ.su/imgs/apple-touch-icon.png" width="42" height="42" align="left" alt="Happ"><strong><a href="https://happ.su/">Happ</a></strong><br><sub>GUI-клиент xray-core и TUN/VPN</sub><br><br>
      <code>4.3.0</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/happ</code>
    </td>
    <td width="50%" valign="top">
      <!-- package-card:tailscale -->
      <img src="https://tailscale.com/favicon.png" width="42" height="42" align="left" alt="Tailscale"><strong><a href="https://tailscale.com/">Tailscale</a></strong><br><sub>Mesh VPN на базе WireGuard</sub><br><br>
      <code>1.102.4</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/tailscale</code>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:telegram -->
      <img src="telegram/telegram-desktop.png" width="42" height="42" align="left" alt="Telegram"><strong><a href="https://desktop.telegram.org/">Telegram</a></strong><br><sub>Официальный десктопный мессенджер</sub><br><br>
      <code>7.2.5</code> · <code>amd64</code><br>
      <code>stplr install nivora/telegram</code>
    </td>
    <td width="50%" valign="top">
      <!-- package-card:vesktop -->
      <img src="https://raw.githubusercontent.com/Vencord/Vesktop/main/build/icon.svg" width="42" height="42" align="left" alt="Vesktop"><strong><a href="vesktop/README.md">Vesktop</a></strong><br><sub>Discord-клиент с интеграцией Vencord</sub><br><br>
      <code>1.6.7</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/vesktop</code>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:yandex-music -->
      <img src="yandex-music/yandex-music.png" width="42" height="42" align="left" alt="Yandex Music"><strong><a href="yandex-music/README.md">Yandex Music</a></strong><br><sub>Официальный клиент музыкального сервиса</sub><br><br>
      <code>5.121.2</code> · <code>amd64</code><br>
      <code>stplr install nivora/yandex-music</code>
    </td>
    <td width="50%" valign="middle"><em>Ещё больше приложений появится после полной проверки рецептов.</em></td>
  </tr>
</table>

### Удалённый доступ

<table>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:parsec -->
      <img src="https://parsec.app/favicon.ico" width="42" height="42" align="left" alt="Parsec"><strong><a href="https://parsec.app/downloads">Parsec</a></strong><br><sub>Удалённый рабочий стол с низкой задержкой</sub><br><br>
      <code>150-104a</code> · <code>amd64</code><br>
      <code>stplr install nivora/parsec</code>
    </td>
    <td width="50%" valign="middle"><em>Подходит для удалённой работы и игрового стриминга.</em></td>
  </tr>
</table>

### AI и разработка

<table>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:chatgpt -->
      <img src="chatgpt/chatgpt.png" width="42" height="42" align="left" alt="ChatGPT"><strong><a href="chatgpt/README.md">ChatGPT</a></strong><br><sub>Десктопный клиент OpenAI</sub><br><br>
      <code>26.917.71314</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/chatgpt</code>
    </td>
    <td width="50%" valign="top">
      <!-- package-card:claude -->
      <img src="claude/claude-tray-orange.png" width="42" height="42" align="left" alt="Claude"><strong><a href="claude/README.md">Claude</a></strong><br><sub>Десктопный клиент Anthropic</sub><br><br>
      <code>2.7032.0</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/claude</code>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:github-desktop -->
      <img src="https://github.githubassets.com/favicons/favicon.png" width="42" height="42" align="left" alt="GitHub Desktop"><strong><a href="github-desktop/README.md">GitHub Desktop</a></strong><br><sub>Официальный код GitHub Desktop, собранный для Linux</sub><br><br>
      <code>3.6.6</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/github-desktop</code>
    </td>
    <td width="50%" valign="top">
      <!-- package-card:vintner -->
      <img src=".github/assets/nivora.png" width="42" height="42" align="left" alt="Vintner"><strong><a href="https://github.com/Cheviiot/vintner">Vintner</a></strong><br><sub>Настоящий MSVC на Linux через Wine</sub><br><br>
      <code>0.5.0</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/vintner</code>
    </td>
  </tr>
</table>

### Рабочий стол

<table>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:anidesk -->
      <img src="anidesk/anidesk.png" width="42" height="42" align="left" alt="AniDesk"><strong><a href="https://github.com/theDesConnet/AniDesk">AniDesk</a></strong><br><sub>Неофициальный desktop-клиент Anixart</sub><br><br>
      <code>0.0.1-beta.7</code> · <code>amd64</code><br>
      <code>stplr install nivora/anidesk</code>
    </td>
    <td width="50%" valign="middle"><em>Приложения, которые органично дополняют Linux-десктоп.</em></td>
  </tr>
</table>

### Игры

<table>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:pineconemc -->
      <img src="pineconemc/pineconemc.svg" width="42" height="42" align="left" alt="PineconeMC"><strong><a href="https://pineconemc.com/">PineconeMC</a></strong><br><sub>Minecraft launcher с Ely.by и offline-аккаунтами</sub><br><br>
      <code>11.1.0</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/pineconemc</code>
    </td>
    <td width="50%" valign="middle"><em>Игровые инструменты с воспроизводимой пакетной установкой.</em></td>
  </tr>
</table>

### Системные инструменты

<table>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:armbian-imager -->
      <img src="https://raw.githubusercontent.com/armbian/imager/main/public/armbian-icon.png" width="42" height="42" align="left" alt="Armbian Imager"><strong><a href="armbian-imager/README.md">Armbian Imager</a></strong><br><sub>Официальная запись образов Armbian</sub><br><br>
      <code>2.0.4</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/armbian-imager</code>
    </td>
    <td width="50%" valign="top">
      <!-- package-card:balena-etcher -->
      <img src="https://raw.githubusercontent.com/balena-io/etcher/master/assets/icon.png" width="42" height="42" align="left" alt="balenaEtcher"><strong><a href="https://etcher.balena.io/">balenaEtcher</a></strong><br><sub>Запись образов на SD-карты и USB</sub><br><br>
      <code>2.1.7</code> · <code>amd64</code><br>
      <code>stplr install nivora/balena-etcher</code>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:distroshelf -->
      <img src="https://raw.githubusercontent.com/ranfdev/DistroShelf/main/data/icons/hicolor/scalable/apps/com.ranfdev.DistroShelf.svg" width="42" height="42" align="left" alt="DistroShelf"><strong><a href="distroshelf/README.md">DistroShelf</a></strong><br><sub>Графическое управление Distrobox-контейнерами</sub><br><br>
      <code>1.5.2</code> · <code>amd64</code><br>
      <code>stplr install nivora/distroshelf</code>
    </td>
    <td width="50%" valign="middle"><em>Инструменты для носителей и контейнеров.</em></td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <!-- package-card:ventoy -->
      <img src="https://raw.githubusercontent.com/ventoy/Ventoy/master/ICON/logo_128.png" width="42" height="42" align="left" alt="Ventoy"><strong><a href="ventoy/README.md">Ventoy</a></strong><br><sub>Мультизагрузочные USB-накопители</sub><br><br>
      <code>1.1.17</code> · <code>amd64</code> <code>arm64</code><br>
      <code>stplr install nivora/ventoy</code>
    </td>
    <td width="50%" valign="middle"><em>Инструменты для носителей, контейнеров и управления пакетами.</em></td>
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
