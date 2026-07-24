# GitHub Desktop

Пакет собирает оригинальный GitHub Desktop для Linux непосредственно из
официального репозитория [`desktop/desktop`](https://github.com/desktop/desktop).
Готовые артефакты, патчи и исходники `shiftkey/desktop` либо других форков не
используются.

GitHub официально выпускает установщики только для macOS и Windows. Linux-сборка
в Nivora поэтому является неофициальным пакетом, но код приложения и закреплённые
submodule-исходники берутся только из официальных репозиториев GitHub.

Тяжёлая сборка выполняется workflow `Сборка GitHub Desktop для Linux` на
нативных GitHub-hosted runner’ах `x64` и `arm64`. Workflow публикует
детерминированно упакованные tar.gz и `SHA256SUMS` в релизе Nivora, а рецепт
скачивает эти готовые артефакты с закреплёнными контрольными суммами.

Установка:

```bash
sudo stplr install nivora/github-desktop
```

Команда запуска:

```bash
github-desktop
```
