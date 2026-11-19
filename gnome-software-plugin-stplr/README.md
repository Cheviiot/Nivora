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

### Готовый RPM без сборки на компьютере

Для x86_64 можно взять готовый RPM в разделе **Artifacts** успешного запуска
[CI в ветке main](https://github.com/Cheviiot/Nivora/actions/workflows/package-ci.yml?query=branch%3Amain),
если в нём проверялся плагин. Артефакт `gnome-software-plugin-stplr-p11-x86_64-…`
хранится 14 дней и содержит тот же RPM, который CI проверил при установке,
обновлении и удалении. Сверьте коммит запуска с нужной версией рецепта.
Распакуйте архив и [установите локальный RPM через APT](https://docs.altlinux.org/ru-RU/alt-workstation/11.2/html/alt-workstation/install-other-packages-rpm.html):
`sudo apt-get install /полный/путь/к/файлу.rpm`.
Для aarch64 используйте сборку через Stapler. Это не отдельный пакетный репозиторий.

## Возврат к штатному плагину

Закройте GNOME Software. Удалите пакет тем способом, которым установили:

- Через Stapler: `sudo stplr remove nivora/gnome-software-plugin-stplr`.
- Через локальный RPM из CI: `sudo apt-get remove gnome-software-plugin-stplr+stplr-default`.
  Имя пакета можно сверить по распакованному файлу: `rpm -qp --queryformat '%{NAME}\n' /полный/путь/к/файлу.rpm`.

Затем установите штатный пакет и снова откройте магазин.

```bash
sudo apt-get update
sudo apt-get install gnome-software-plugin-stplr
```

[Подключение Nivora](../.github/docs/installation.md) · [Каталог приложений](../README.md)
