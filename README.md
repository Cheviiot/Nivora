<p align="center">
  <img src=".github/assets/nivora.png" width="112" height="112" alt="Nivora">
</p>

<h1 align="center">Nivora</h1>

<p align="center">
  <strong>Независимый каталог Linux-приложений для Stapler</strong>
</p>

<p align="center">
  <a href="https://stplr.dev/docs/intro/"><img src="https://img.shields.io/badge/Stapler-Community%20Repo-6366F1?style=for-the-badge" alt="Stapler Community Repo"></a>
  <img src="https://img.shields.io/badge/пакетов-16-2ea043?style=for-the-badge" alt="16 пакетов">
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
**16 пакетов** · **6 категорий** · `amd64`, `arm64` и `all`

## Подключение

Требуется [Stapler](https://stplr.dev/docs/intro/) `v0.1.1` или новее.

```bash
sudo stplr repo add nivora https://github.com/Cheviiot/Nivora.git
sudo stplr refresh
```

Установка пакета:

```bash
sudo stplr install nivora/chatgpt
```

Проверить описание до установки:

```bash
stplr info nivora/chatgpt
```

Индекс меняется только явной командой `sudo stplr refresh`: документация и
Nivora CLI не полагаются на `autoPull`. Старое имя пакета `codex` заменено на
`chatgpt`; Nivora CLI принимает его как устаревший ввод и предупреждает о замене.

## Совместимость со Stapler

| Уровень | Версия | Назначение |
|:--|:--|:--|
| Stable, обязательный | `v0.1.1` | минимальная поддерживаемая версия и блокирующий пользовательский контракт |
| Main canary | `9df2b9284d3a37cdc418cef2e77781bac3b8dc3e` | раннее обнаружение несовместимости; не заменяет stable и не считается релизом |

Изменение проходит только когда обязательная stable-проверка успешна. Canary
закрепляется по commit, обновляется отдельно и не даёт права использовать ещё
не выпущенные функции в рецептах. Политика обходов upstream и условия их удаления
описаны в [руководстве сопровождающего](.github/docs/maintenance.md).
Целевая совместимость и ограничения каждого пакета зафиксированы в
[машиночитаемой матрице](.github/support-matrix.toml); `unsupported` означает,
что Stapler должен отклонить такую цель до сборки. На текущем этапе только
`nivora-cli` на Ubuntu 24.04 (`amd64` и native `arm64`) имеет уровень `verified`:
обе ячейки блокирующе собирают DEB, проверяют его metadata, устанавливают,
запускают безопасный smoke и удаляют пакет. Остальные разрешённые цели честно
помечены `partial` или `experimental`, пока для них не появится такой же gate.

## Каталог

Название ведёт на источник приложения. `all` означает, что сам пакет не
содержит архитектурно-зависимых бинарников.

### Интернет, сеть и VPN

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="https://happ.su/imgs/apple-touch-icon.png" width="32" height="32" alt="Happ"> | [Happ](https://happ.su/) | `4.1.3` | `amd64`, `arm64` | `stplr install nivora/happ` |
| <img src="https://tailscale.com/favicon.png" width="32" height="32" alt="Tailscale"> | [Tailscale](https://tailscale.com/) | `1.102.3` | `amd64`, `arm64` | `stplr install nivora/tailscale` |
| <img src="telegram/telegram-desktop.png" width="32" height="32" alt="Telegram"> | [Telegram](https://desktop.telegram.org/) | `7.1.5` | `amd64` | `stplr install nivora/telegram` |
| <img src="https://raw.githubusercontent.com/Vencord/Vesktop/main/build/icon.svg" width="32" height="32" alt="Vesktop"> | [Vesktop](vesktop/README.md) | `1.6.7` | `amd64`, `arm64` | `stplr install nivora/vesktop` |
| <img src="yandex-music/yandex-music.png" width="32" height="32" alt="Yandex Music"> | [Yandex Music](yandex-music/README.md) | `5.118.1` | `amd64` | `stplr install nivora/yandex-music` |

### Удалённый доступ

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="https://parsec.app/favicon.ico" width="32" height="32" alt="Parsec"> | [Parsec](https://parsec.app/downloads) | `150-104a` | `amd64` | `stplr install nivora/parsec` |

### AI и разработка

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="chatgpt/chatgpt.png" width="32" height="32" alt="ChatGPT"> | [ChatGPT](chatgpt/README.md) | `26.901.31953` | `amd64`, `arm64` | `stplr install nivora/chatgpt` |
| <img src="claude/claude-tray-orange.png" width="32" height="32" alt="Claude"> | [Claude](claude/README.md) | `1.40609.1` | `amd64`, `arm64` | `stplr install nivora/claude` |
| <img src="https://github.githubassets.com/favicons/favicon.png" width="32" height="32" alt="GitHub Desktop"> | [GitHub Desktop](github-desktop/README.md) | `3.6.5` | `amd64`, `arm64` | `stplr install nivora/github-desktop` |
| | [Vintner](https://github.com/Cheviiot/vintner) | `0.5.0` | `amd64`, `arm64` | `stplr install nivora/vintner` |

### Рабочий стол

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="anidesk/anidesk.png" width="32" height="32" alt="AniDesk"> | [AniDesk](https://github.com/theDesConnet/AniDesk) | `0.0.1-beta.7` | `amd64` | `stplr install nivora/anidesk` |

### Игры

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="pineconemc/pineconemc.svg" width="32" height="32" alt="PineconeMC"> | [PineconeMC](https://pineconemc.com/) | `11.0.3` | `amd64`, `arm64` | `stplr install nivora/pineconemc` |

### Системные инструменты

| | Приложение | Версия | Архитектуры | Установка |
|:---:|---|:--:|:--:|---|
| <img src="https://raw.githubusercontent.com/balena-io/etcher/master/assets/icon.png" width="32" height="32" alt="balenaEtcher"> | [balenaEtcher](https://etcher.balena.io/) | `2.1.6` | `amd64` | `stplr install nivora/balena-etcher` |
| <img src="https://raw.githubusercontent.com/ranfdev/DistroShelf/main/data/icons/hicolor/scalable/apps/com.ranfdev.DistroShelf.svg" width="32" height="32" alt="DistroShelf"> | [DistroShelf](distroshelf/README.md) | `1.5.2` | `amd64` | `stplr install nivora/distroshelf` |
| <img src=".github/assets/nivora.png" width="32" height="32" alt="Nivora CLI"> | [Nivora CLI](nivora-cli/README.md) | `1.1.0` | `all` | `stplr install nivora/nivora-cli` |
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
- Проприетарные артефакты не зеркалируются в релизы или постоянные кэши Nivora.
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
