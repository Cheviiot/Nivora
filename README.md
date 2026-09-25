<p align="center">
  <img src=".github/assets/readme-hero.png" width="100%" alt="Nivora — приложения для ALT Linux">
</p>

<p align="center">
  <a href="#совместимость"><img src="https://img.shields.io/badge/ALT-p11%20%C2%B7%20Sisyphus-39cfa4?style=flat-square" alt="ALT p11 и Sisyphus"></a>
  <a href="https://stplr.dev/docs/intro/"><img src="https://img.shields.io/badge/Stapler-v0.1.1-1ab8cd?style=flat-square" alt="Stapler v0.1.1"></a>
  <a href="https://github.com/Cheviiot/Nivora/actions/workflows/quality.yml"><img src="https://img.shields.io/github/actions/workflow/status/Cheviiot/Nivora/quality.yml?branch=main&amp;style=flat-square&amp;label=CI" alt="Статус проверок репозитория"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Рецепты-MIT-8b5cf6?style=flat-square" alt="Рецепты под лицензией MIT"></a>
</p>

<p align="center">
  Приложения для общения, работы и повседневных задач — с установкой через Stapler.
</p>

<p align="center">
  <a href="#быстрый-старт">Быстрый старт</a> &nbsp;·&nbsp;
  <a href="#каталог">Каталог</a> &nbsp;·&nbsp;
  <a href="#совместимость">Совместимость</a> &nbsp;·&nbsp;
  <a href="#обновление">Обновление</a> &nbsp;·&nbsp;
  <a href="#документация">Документация</a>
</p>

<!-- package-count -->
<p align="center"><strong>16 пакетов</strong> &nbsp;·&nbsp; 4 категории &nbsp;·&nbsp; Открытые рецепты</p>

## Быстрый старт

Нужны **ALT Linux p11 или Sisyphus** и установленный
[Stapler](https://stplr.dev/docs/intro/). Поддерживаемая версия Stapler — `v0.1.1`.

```bash
# 1. Подключить Nivora
sudo stplr repo add nivora https://github.com/Cheviiot/Nivora.git

# 2. Обновить список пакетов
sudo stplr refresh

# 3. Посмотреть описание и установить приложение
stplr info nivora/chatgpt
sudo stplr install nivora/chatgpt
```

> Nivora — независимый репозиторий сообщества. У проприетарных приложений
> действуют условия их разработчиков: при интерактивной установке Stapler
> предложит прочитать и принять их.

## Каталог

Название открывает страницу пакета с описанием и инструкцией. Справа указаны
**версия**, **архитектуры рецепта** и **идентификатор установки**.

```bash
sudo stplr install nivora/имя-пакета
```

<!-- catalog:start -->
### Интернет, сеть и VPN

<table width="100%">
  <tr><!-- package-card:happ -->
    <td width="400" nowrap><img src="https://happ.su/imgs/apple-touch-icon.png" width="24" height="24" alt=""> &nbsp;<a href="happ/README.md"><strong>Happ</strong></a><br><sub>VPN-клиент на базе Xray</sub></td>
    <td align="right" nowrap><code>4.3.0</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/happ</code></td>
  </tr>
  <tr><!-- package-card:tailscale -->
    <td width="400" nowrap><img src="https://tailscale.com/favicon.png" width="24" height="24" alt=""> &nbsp;<a href="tailscale/README.md"><strong>Tailscale</strong></a><br><sub>Частная сеть между устройствами</sub></td>
    <td align="right" nowrap><code>1.102.4</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/tailscale</code></td>
  </tr>
  <tr><!-- package-card:telegram -->
    <td width="400" nowrap><img src="telegram/telegram-desktop.png" width="24" height="24" alt=""> &nbsp;<a href="telegram/README.md"><strong>Telegram</strong></a><br><sub>Сообщения, звонки и каналы</sub></td>
    <td align="right" nowrap><code>7.2.5</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/telegram</code></td>
  </tr>
  <tr><!-- package-card:vesktop -->
    <td width="400" nowrap><img src="https://raw.githubusercontent.com/Vencord/Vesktop/main/build/icon.svg" width="24" height="24" alt=""> &nbsp;<a href="vesktop/README.md"><strong>Vesktop</strong></a><br><sub>Discord-клиент с Vencord</sub></td>
    <td align="right" nowrap><code>1.6.7</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/vesktop</code></td>
  </tr>
</table>

### AI и разработка

<table width="100%">
  <tr><!-- package-card:chatgpt -->
    <td width="400" nowrap><img src="chatgpt/chatgpt.png" width="24" height="24" alt=""> &nbsp;<a href="chatgpt/README.md"><strong>ChatGPT</strong></a><br><sub>Приложение OpenAI со встроенным Codex</sub></td>
    <td align="right" nowrap><code>26.917.71314</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/chatgpt</code></td>
  </tr>
  <tr><!-- package-card:claude -->
    <td width="400" nowrap><img src="claude/claude-tray-orange.png" width="24" height="24" alt=""> &nbsp;<a href="claude/README.md"><strong>Claude</strong></a><br><sub>Десктопное приложение Anthropic</sub></td>
    <td align="right" nowrap><code>2.7032.0</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/claude</code></td>
  </tr>
  <tr><!-- package-card:github-desktop -->
    <td width="400" nowrap><img src="https://github.githubassets.com/favicons/favicon.png" width="24" height="24" alt=""> &nbsp;<a href="github-desktop/README.md"><strong>GitHub Desktop</strong></a><br><sub>Linux-сборка из официальных исходников</sub></td>
    <td align="right" nowrap><code>3.6.6</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/github-desktop</code></td>
  </tr>
  <tr><!-- package-card:vintner -->
    <td width="400" nowrap><img src=".github/assets/nivora.png" width="24" height="24" alt=""> &nbsp;<a href="vintner/README.md"><strong>Vintner</strong></a><br><sub>Инструменты MSVC в Linux через Wine</sub></td>
    <td align="right" nowrap><code>0.5.0</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/vintner</code></td>
  </tr>
</table>

### Медиа и игры

<table width="100%">
  <tr><!-- package-card:yandex-music -->
    <td width="400" nowrap><img src="yandex-music/yandex-music.png" width="24" height="24" alt=""> &nbsp;<a href="yandex-music/README.md"><strong>Яндекс Музыка</strong></a><br><sub>Музыка, подкасты и персональные подборки</sub></td>
    <td align="right" nowrap><code>5.121.2</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/yandex-music</code></td>
  </tr>
  <tr><!-- package-card:anidesk -->
    <td width="400" nowrap><img src="anidesk/anidesk.png" width="24" height="24" alt=""> &nbsp;<a href="anidesk/README.md"><strong>AniDesk</strong></a><br><sub>Десктопный клиент Anixart</sub></td>
    <td align="right" nowrap><code>0.0.1-beta.7</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/anidesk</code></td>
  </tr>
  <tr><!-- package-card:pineconemc -->
    <td width="400" nowrap><img src="pineconemc/pineconemc.svg" width="24" height="24" alt=""> &nbsp;<a href="pineconemc/README.md"><strong>PineconeMC</strong></a><br><sub>Лаунчер Minecraft с поддержкой Ely.by</sub></td>
    <td align="right" nowrap><code>11.1.0</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/pineconemc</code></td>
  </tr>
  <tr><!-- package-card:parsec -->
    <td width="400" nowrap><img src="https://parsec.app/favicon.ico" width="24" height="24" alt=""> &nbsp;<a href="parsec/README.md"><strong>Parsec</strong></a><br><sub>Доступ к удалённому рабочему столу</sub></td>
    <td align="right" nowrap><code>150-104a</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/parsec</code></td>
  </tr>
</table>

### Системные инструменты

<table width="100%">
  <tr><!-- package-card:armbian-imager -->
    <td width="400" nowrap><img src="https://raw.githubusercontent.com/armbian/imager/main/public/armbian-icon.png" width="24" height="24" alt=""> &nbsp;<a href="armbian-imager/README.md"><strong>Armbian Imager</strong></a><br><sub>Выбор и запись образов Armbian</sub></td>
    <td align="right" nowrap><code>2.0.4</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/armbian-imager</code></td>
  </tr>
  <tr><!-- package-card:balena-etcher -->
    <td width="400" nowrap><img src="https://raw.githubusercontent.com/balena-io/etcher/master/assets/icon.png" width="24" height="24" alt=""> &nbsp;<a href="balena-etcher/README.md"><strong>balenaEtcher</strong></a><br><sub>Запись образов на SD-карты и USB</sub></td>
    <td align="right" nowrap><code>2.1.7</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/balena-etcher</code></td>
  </tr>
  <tr><!-- package-card:distroshelf -->
    <td width="400" nowrap><img src="https://raw.githubusercontent.com/ranfdev/DistroShelf/main/data/icons/hicolor/scalable/apps/com.ranfdev.DistroShelf.svg" width="24" height="24" alt=""> &nbsp;<a href="distroshelf/README.md"><strong>DistroShelf</strong></a><br><sub>Графическое управление Distrobox</sub></td>
    <td align="right" nowrap><code>1.5.2</code></td>
    <td nowrap><code>amd64</code></td>
    <td nowrap><code>nivora/distroshelf</code></td>
  </tr>
  <tr><!-- package-card:ventoy -->
    <td width="400" nowrap><img src="https://raw.githubusercontent.com/ventoy/Ventoy/master/ICON/logo_128.png" width="24" height="24" alt=""> &nbsp;<a href="ventoy/README.md"><strong>Ventoy</strong></a><br><sub>Несколько загрузочных образов на одной флешке</sub></td>
    <td align="right" nowrap><code>1.1.17</code></td>
    <td nowrap><code>amd64</code> <code>arm64</code></td>
    <td nowrap><code>nivora/ventoy</code></td>
  </tr>
</table>
<!-- catalog:end -->

## Совместимость

Nivora предназначена **только для ALT Linux**. Архитектуру выбирайте по строке
нужного приложения в каталоге.

| Архитектура | ALT p11 | ALT Sisyphus |
|:--|:--|:--|
| **amd64** · x86_64 | Проверки сборки и установки в CI | Проверки сборки и установки в CI |
| **arm64** · aarch64 | Заявлена для части пакетов, без CI | Заявлена для части пакетов, без CI |

Для `amd64` также настроены проверки состава пакета, базового запуска и
удаления. Для `arm64` Stapler собирает пакет на машине пользователя.
Особенности приложений и границы проверок — в
[матрице поддержки](.github/support-matrix.toml).

## Обновление

```bash
sudo stplr refresh
sudo stplr upgrade
```

`refresh` загружает актуальные рецепты, `upgrade` обновляет установленные
пакеты. Пользовательские настройки сохраняются при обновлении и обычном
удалении; отключённые системные службы остаются отключёнными.

## Документация

| Задача | Куда перейти |
|:--|:--|
| Добавить приложение или улучшить рецепт | [Участие в проекте](CONTRIBUTING.md) |
| Собрать пакет и разобраться в обновлениях | [Руководство сопровождающего](.github/docs/maintenance.md) |
| Узнать об источниках, проверках и лицензиях | [Модель доверия](.github/docs/security-model.md) |
| Сообщить об уязвимости | [Политика безопасности](SECURITY.md) |
| Посмотреть, что изменилось | [История изменений](CHANGELOG.md) |

---

<p align="center">
  <sub>Сделано для сообщества ALT Linux · <a href="LICENSE">Рецепты — MIT</a> · © 2026 Cheviiot</sub>
</p>
