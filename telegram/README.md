<p align="center">
  <img src="telegram-desktop.png" width="96" height="96" alt="Telegram">
</p>

<h1 align="center">Telegram</h1>

<p align="center">
  Официальный клиент мессенджера Telegram
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--only-blue?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64-2ea043?style=for-the-badge" alt="amd64">
</p>

---

## Установка

```bash
sudo stplr install nivora/telegram
```

Каталог и package ID переименованы с `telegram-desktop`. `replaces` не
включает старое имя (это разрешено только для `claude` в `validate_repo.py`),
поэтому у кого установлен `telegram-desktop`, нужно вручную
`stplr install telegram` и `stplr remove telegram-desktop`.

## Возможности

Telegram Desktop — облачная синхронизация чатов, голосовые и видеозвонки, без
ограничений на размер файлов и историю медиа.

## Технические детали

Пакет собирается из официального статически собранного Linux-архива
`tsetup.<version>.tar.xz` с [desktop.telegram.org](https://desktop.telegram.org/),
без сторонних патчей кода. Сохранены официальные desktop-id
`org.telegram.desktop` и WM-класс `TelegramDesktop`.

Upstream-бинарник сам умеет переустанавливать копию своего `.desktop`/`.service`
файла в `~/.local/share/applications` при каждом запуске — это логика
`InstallLauncher()` в `specific_linux.cpp`, рассчитанная на self-contained
тарболы без пакетного менеджера. Для системного пакета это создаёт дублирующий
значок запуска и путает Wayland `app_id` окна с иконкой. Telegram документирует
собственный опт-аут именно для дистрибутивных сборок:
`Launcher::ComputeExternalUpdater()` ищет в `<exe-dir>/externalupdater.d/`
файл, содержащий полный путь к своему исполняемому файлу, — при совпадении
вызывается `SetUpdaterDisabledAtStartup()`. Пакет ставит такой файл-маркер, и
это одновременно решает обе проблемы: не создаётся теневой `.desktop`/`.service`,
а `desktopFileName()` использует чистый `org.telegram.desktop` id вместо
захешированного по пути установки — тот же id, что и в поставляемом
`.desktop`-файле.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
