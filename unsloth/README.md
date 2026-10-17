# Unsloth Desktop

[Unsloth Desktop](https://unsloth.ai/download/linux) — официальное приложение
проекта Unsloth для запуска и дообучения LLM и моделей диффузии на локальном
железе: GPU NVIDIA, AMD или Intel, Vulkan либо CPU, без облака. Nivora
упаковывает официальный Linux DEB для ALT Linux p11 и Sisyphus; доступна
архитектура `amd64`.

## Установка

```bash
sudo stplr install nivora/unsloth
```

Запустите **Unsloth** из меню приложений или командой `unsloth-studio`.
Модели скачиваются из сети при первом использовании и хранятся в домашнем
каталоге; они не удаляются вместе с пакетом.

Пакет устанавливает именно десктопное приложение. Отдельная установка
Unsloth Studio (через `install.sh` внутри `/usr/lib/Unsloth/`) в него не
входит и для работы десктопа не требуется. Если апстримный DEB Unsloth был
установлен вручную, удалите его перед установкой `nivora/unsloth`.

Источник: [релиз v0.1.908-beta](https://github.com/unslothai/unsloth/releases/tag/v0.1.908-beta).
Лицензия приложения — [Apache-2.0](https://github.com/unslothai/unsloth) (код проекта)
и AGPL-3.0-only (`install.sh` студии).

[Назад к каталогу Nivora](../README.md).
