<p align="center">
  <img src=".github/assets/nivora.png" width="96" height="96" alt="Nivora">
</p>

# Nivora

**Независимый каталог Linux-приложений для Stapler.**

Nivora предлагает открытые рецепты упаковки десктопных приложений и
инструментов, которых может не быть в системном репозитории. Это не
официальный репозиторий Stapler и не официальные пакеты upstream-проектов.

<!-- package-count -->
**15 пакетов** · **6 категорий** · `amd64`, `arm64` и `all`

[![Проверка Nivora](https://github.com/Cheviiot/Nivora/actions/workflows/quality.yml/badge.svg)](https://github.com/Cheviiot/Nivora/actions/workflows/quality.yml)

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

### Сеть и VPN

| Приложение | Версия | Архитектуры | Установка |
|:--|:--:|:--:|:--|
| [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) | `2.5.1` | `amd64`, `arm64` | `stplr install nivora/clash-verge-rev` |
| [Happ](https://happ.su/) | `3.1.0` | `amd64`, `arm64` | `stplr install nivora/happ` |
| [NetBird](https://netbird.io/) | `0.74.7` | `amd64`, `arm64` | `stplr install nivora/netbird` |
| [Tailscale](https://tailscale.com/) | `1.98.9` | `amd64`, `arm64` | `stplr install nivora/tailscale` |

### Удалённый доступ

| Приложение | Версия | Архитектуры | Установка |
|:--|:--:|:--:|:--|
| [Parsec](https://parsec.app/downloads) | `150-104a` | `amd64` | `stplr install nivora/parsec` |

### AI и разработка

| Приложение | Версия | Архитектуры | Установка |
|:--|:--:|:--:|:--|
| [Chatbox](https://chatboxai.app/ru) | `1.20.3` | `amd64`, `arm64` | `stplr install nivora/chatbox` |
| [Claude](https://code.claude.com/docs/en/desktop-quickstart) | `1.22209.0` | `amd64`, `arm64` | `stplr install nivora/claude-desktop` |
| [Codex](https://github.com/Boria138/codex-app-linux) | `26.715.31925` | `amd64` | `stplr install nivora/codex` |
| [OpenCode](https://opencode.ai/) | `1.18.3` | `amd64`, `arm64` | `stplr install nivora/opencode` |

### Рабочий стол

| Приложение | Версия | Архитектуры | Установка |
|:--|:--:|:--:|:--|
| [Adwyra](https://github.com/Cheviiot/Adwyra) | `0.6.1` | `all` | `stplr install nivora/adwyra` |
| [AniDesk](https://github.com/theDesConnet/AniDesk) | `0.0.1-beta.7` | `amd64` | `stplr install nivora/anidesk` |

### Игры

| Приложение | Версия | Архитектуры | Установка |
|:--|:--:|:--:|:--|
| [PineconeMC](https://pineconemc.com/) | `11.0.3` | `amd64`, `arm64` | `stplr install nivora/pineconemc` |
| [Vual](https://github.com/Cheviiot/Vual) | `0.3.1` | `all` | `stplr install nivora/vual` |

### Системные инструменты

| Приложение | Версия | Архитектуры | Установка |
|:--|:--:|:--:|:--|
| [Fisher](https://github.com/jorgebucaran/fisher) | `4.4.8` | `all` | `stplr install nivora/fisher` |
| [Nivora Stapler Helper](docs/packages/nivora-stplr.md) | `0.2.0` | `all` | `stplr install nivora/nivora-stplr` |

## Обновление

```bash
sudo stplr refresh
sudo stplr upgrade
```

Рецепты сохраняют пути пользовательских конфигураций. Обычное обновление и
удаление пакета не должно сбрасывать настройки или выполнять logout.

## Переход с Luma

Удалять приложения не нужно. Из-за привязки установленных Stapler-пакетов к имени
репозитория нужна одноразовая проверяемая миграция:

```bash
sudo stplr repo add nivora https://github.com/Cheviiot/Nivora.git
sudo stplr refresh
sudo stplr install nivora/nivora-stplr
sudo nivora-migrate-from-luma --yes
sudo stplr upgrade
```

Мигратор заменяет только установленные пакеты, проверяет новые package ID и
удаляет старую запись репозитория только после успеха. Данные в домашнем
каталоге не изменяются. [Подробная инструкция](docs/migration-from-luma.md).

## Безопасность и доверие

- Каждый `Staplerfile` доступен для проверки.
- Файлы загружаются из указанных upstream-источников.
- SHA-256 проверяет целостность загрузки, но не делает upstream автоматически безопасным.
- Условия проприетарных приложений определяются их разработчиками.
- Наличие CI не обещает абсолютную безопасность или совместимость с любой системой.

Подробнее: [модель доверия](docs/security-model.md) и [политика безопасности](SECURITY.md).

## Для сопровождающих

```bash
tools/run_checks.sh
tools/package_updates.sh check-all
tools/clean_build.sh --all
tools/verify_artifacts.sh --all
tools/test_package_transitions.sh
```

Правила изменений описаны в [CONTRIBUTING.md](CONTRIBUTING.md), а порядок сопровождения — в
[docs/maintenance.md](docs/maintenance.md).
