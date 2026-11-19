# Плагин Stapler для GNOME Software

Подключает каталоги Stapler к магазину приложений GNOME. Из карточки приложения можно запустить установку, обновление или удаление, а после установки — открыть приложение. Nivora собирает плагин из закреплённого снимка исходников для GNOME Software в p11. [Проект Stapler](https://altlinux.space/stapler/gnome-software-plugin-stplr)

ALT Linux p11 · x86_64 · aarch64 (предварительная поддержка)

## Установка

**Лицензия плагина** — [GPL-3.0-or-later](LICENSE).

```bash
sudo stplr refresh
sudo stplr install nivora/gnome-software-plugin-stplr
```

Пакет Nivora заменяет штатный плагин p11. Полностью закройте и снова откройте GNOME Software. Если приложение доступно из нескольких источников, выберите **Nivora** в его карточке.

## Возврат к штатному плагину

Закройте GNOME Software и выполните команды ниже. После установки снова откройте магазин.

```bash
sudo stplr remove nivora/gnome-software-plugin-stplr
sudo apt-get update
sudo apt-get install gnome-software-plugin-stplr
```

[Подключение Nivora](../.github/docs/installation.md) · [Каталог приложений](../README.md)
