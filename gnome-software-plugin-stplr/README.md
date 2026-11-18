# GNOME Software: плагин Stapler

Служебный пакет для ALT Linux p11, который подключает каталоги Stapler к
GNOME Software: поиск, установка, обновление, удаление и открытие приложений.
Плагин участвует в автоматическом обслуживании Nivora; на главной витрине
он не отображается.

## Установка

После [подключения Nivora](../.github/docs/installation.md):

```bash
sudo stplr refresh
sudo stplr install nivora/gnome-software-plugin-stplr
```

Пакет заменяет штатный плагин p11. Полностью закройте и снова откройте
GNOME Software, чтобы он загрузил новую библиотеку.

Совместимость, обновление, диагностика и возврат к штатной версии описаны
в [руководстве по GNOME Software](../.github/docs/gnome-software.md).
Точные версия, commit исходников и контрольные суммы находятся в [Staplerfile](Staplerfile).

[Официальный проект](https://altlinux.space/stapler/gnome-software-plugin-stplr) ·
[GPL-3.0-or-later](LICENSE)
