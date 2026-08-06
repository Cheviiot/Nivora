<p align="center">
  <img src="https://github.githubassets.com/favicons/favicon.png" width="96" height="96" alt="GitHub Desktop">
</p>

<h1 align="center">GitHub Desktop</h1>

<p align="center">
  GitHub Desktop, собранный из официальных исходников для Linux
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-brightgreen?style=for-the-badge" alt="Лицензия">
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64, arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/github-desktop
```

Команда запуска:

```bash
github-desktop
```

## Технические детали

Пакет собирает оригинальный GitHub Desktop для Linux непосредственно из
официального репозитория [`desktop/desktop`](https://github.com/desktop/desktop).
Готовые артефакты, патчи и исходники стороннего форка `shiftkey/desktop`
не используются.

GitHub официально выпускает установщики только для macOS и Windows — Linux-
сборка в Nivora поэтому неофициальна, но код приложения и закреплённые
submodule-исходники берутся исключительно из официальных репозиториев GitHub.

Тяжёлая сборка выполняется отдельным workflow `Сборка GitHub Desktop для
Linux` на нативных GitHub-hosted runner'ах `x64` и `arm64`. Workflow публикует
детерминированно упакованные `tar.gz` и `SHA256SUMS` в релизе Nivora, а
рецепт скачивает эти готовые артефакты с закреплёнными контрольными суммами.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
