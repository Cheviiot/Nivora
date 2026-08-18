<p align="center">
  <img src=".github/assets/nivora.png" width="112" height="112" alt="Nivora">
</p>

<h1 align="center">Nivora</h1>

<p align="center">
  <strong>Независимый каталог Linux-приложений для Stapler</strong>
</p>

<p align="center">
  <a href="https://stplr.dev/docs/intro/"><img src="https://img.shields.io/badge/Stapler-Community%20Repo-6366F1?style=for-the-badge" alt="Stapler Community Repo"></a>
  <img src="https://img.shields.io/badge/пакетов-22-2ea043?style=for-the-badge" alt="22 пакета">
  <a href="https://github.com/Cheviiot/Nivora/actions/workflows/quality.yml"><img src="https://img.shields.io/github/actions/workflow/status/Cheviiot/Nivora/quality.yml?branch=main&style=for-the-badge&label=CI" alt="CI"></a>
</p>

<p align="center">
  Открытые рецепты упаковки десктопных приложений и инструментов, которых
  может не быть в системном репозитории. Это не официальный репозиторий
  Stapler и не официальные пакеты upstream-проектов.
</p>

<p align="center">
  <a href="CHANGELOG.md">Changelog</a> •
  <a href="CONTRIBUTING.md">Контрибьюторам</a> •
  <a href="SECURITY.md">Безопасность</a> •
  <a href="LICENSE">Лицензия</a>
</p>

<!-- package-count -->
**22 пакета** · **6 категорий** · `amd64`, `arm64` и `all`

## Подключение

Требуется [Stapler](https://stplr.dev/docs/intro/) `v0.1.1` или новее.

```bash
sudo stplr repo add nivora https://github.com/Cheviiot/Nivora.git
sudo stplr refresh
```

Установка пакета:

```bash
sudo stplr install nivora/codex
```

Проверить описание до установки:

```bash
stplr info nivora/codex
```

## Каталог

Название ведёт на источник приложения. `all` означает, что сам пакет не
содержит архитектурно-зависимых бинарников.

### Интернет, сеть и VPN

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="https://happ.su/imgs/apple-touch-icon.png" width="32" height="32" alt="Happ"> | [Happ](https://happ.su/) | `3.3.6` | `amd64`, `arm64` | `stplr install nivora/happ` |
| <img src="https://tailscale.com/favicon.png" width="32" height="32" alt="Tailscale"> | [Tailscale](https://tailscale.com/) | `1.102.2` | `amd64`, `arm64` | `stplr install nivora/tailscale` |
| <img src="telegram/telegram-desktop.png" width="32" height="32" alt="Telegram"> | [Telegram](https://desktop.telegram.org/) | `7.0.9` | `amd64` | `stplr install nivora/telegram` |
| <img src="https://raw.githubusercontent.com/Vencord/Vesktop/main/build/icon.svg" width="32" height="32" alt="Vesktop"> | [Vesktop](vesktop/README.md) | `1.6.7` | `amd64`, `arm64` | `stplr install nivora/vesktop` |
| <img src="https://browser.yandex.ru/apple-touch-icon.png" width="32" height="32" alt="Яндекс Браузер"> | [Яндекс Браузер](https://browser.yandex.ru/) | `26.6.1.1083` | `amd64` | `stplr install nivora/yandex-browser-stable` |
| <img src="yandex-music/yandex-music.png" width="32" height="32" alt="Yandex Music"> | [Yandex Music](yandex-music/README.md) | `5.115.3` | `amd64` | `stplr install nivora/yandex-music` |

### Удалённый доступ

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="https://parsec.app/favicon.ico" width="32" height="32" alt="Parsec"> | [Parsec](https://parsec.app/downloads) | `150-104a` | `amd64` | `stplr install nivora/parsec` |

### AI и разработка

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="claude/claude-tray-orange.png" width="32" height="32" alt="Claude"> | [Claude](claude/README.md) | `1.32352.1` | `amd64`, `arm64` | `stplr install nivora/claude` |
| <img src="claude/claude-alt.png" width="32" height="32" alt="ClaudeAlt"> | [ClaudeAlt](claude-alt/README.md) | `1.32352.1` | `amd64`, `arm64` | `stplr install nivora/claude-alt` |
| <img src="codex/codex-app.png" width="32" height="32" alt="Codex"> | [Codex](codex/README.md) | `26.721.81911` | `amd64` | `stplr install nivora/codex` |
| <img src="https://github.githubassets.com/favicons/favicon.png" width="32" height="32" alt="GitHub Desktop"> | [GitHub Desktop](github-desktop/README.md) | `3.6.4` | `amd64`, `arm64` | `stplr install nivora/github-desktop` |
| <img src="https://opencode.ai/apple-touch-icon.png" width="32" height="32" alt="OpenCode"> | [OpenCode](https://opencode.ai/) | `1.18.18` | `amd64`, `arm64` | `stplr install nivora/opencode` |
| <img src="openwhispr/openwhispr.png" width="32" height="32" alt="OpenWhispr"> | [OpenWhispr](openwhispr/README.md) | `1.8.3` | `amd64` | `stplr install nivora/openwhispr` |
| | [Vintner](https://github.com/Cheviiot/vintner) | `0.5.0` | `amd64`, `arm64` | `stplr install nivora/vintner` |

### Рабочий стол

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="anidesk/anidesk.png" width="32" height="32" alt="AniDesk"> | [AniDesk](https://github.com/theDesConnet/AniDesk) | `0.0.1-beta.7` | `amd64` | `stplr install nivora/anidesk` |

### Игры

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="pineconemc/pineconemc.svg" width="32" height="32" alt="PineconeMC"> | [PineconeMC](https://pineconemc.com/) | `11.0.3` | `amd64`, `arm64` | `stplr install nivora/pineconemc` |
| <img src="https://raw.githubusercontent.com/Cheviiot/Vual/main/data/Vual.png" width="32" height="32" alt="Vual"> | [Vual](https://github.com/Cheviiot/Vual) | `0.3.1` | `all` | `stplr install nivora/vual` |

### Системные инструменты

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="https://raw.githubusercontent.com/balena-io/etcher/master/assets/icon.png" width="32" height="32" alt="balenaEtcher"> | [balenaEtcher](https://etcher.balena.io/) | `2.1.6` | `amd64` | `stplr install nivora/balena-etcher` |
| <img src="https://raw.githubusercontent.com/ranfdev/DistroShelf/main/data/icons/hicolor/scalable/apps/com.ranfdev.DistroShelf.svg" width="32" height="32" alt="DistroShelf"> | [DistroShelf](distroshelf/README.md) | `1.5.2` | `amd64` | `stplr install nivora/distroshelf` |
| | [Fisher](https://github.com/jorgebucaran/fisher) | `4.4.8` | `all` | `stplr install nivora/fisher` |
| <img src=".github/assets/nivora.png" width="32" height="32" alt="Nivora CLI"> | [Nivora CLI](nivora-cli/README.md) | `1.0.0` | `all` | `stplr install nivora/nivora-cli` |
| <img src="https://raw.githubusercontent.com/ventoy/Ventoy/master/ICON/logo_128.png" width="32" height="32" alt="Ventoy"> | [Ventoy](ventoy/README.md) | `1.1.17` | `amd64`, `arm64` | `stplr install nivora/ventoy` |

## Обновление

```bash
sudo stplr refresh
sudo stplr upgrade
```

Рецепты сохраняют пути пользовательских конфигураций. Обычное обновление и
удаление пакета не должно сбрасывать настройки или выполнять logout.

## Безопасность и доверие

- Каждый `Staplerfile` доступен для проверки.
- Файлы загружаются из указанных upstream-источников.
- SHA-256 проверяет целостность загрузки, но не делает upstream автоматически безопасным.
- Условия проприетарных приложений определяются их разработчиками.
- Наличие CI не обещает абсолютную безопасность или совместимость с любой системой.

Подробнее: [модель доверия](.github/docs/security-model.md) и [политика безопасности](SECURITY.md).

## Для сопровождающих

```bash
.github/tools/run_checks.sh
.github/tools/package_updates.sh check-all
.github/tools/clean_build.sh --all
.github/tools/verify_artifacts.sh --all
.github/tools/test_package_lifecycle.sh
```

Правила изменений описаны в [CONTRIBUTING.md](CONTRIBUTING.md), а порядок сопровождения — в
[.github/docs/maintenance.md](.github/docs/maintenance.md).
