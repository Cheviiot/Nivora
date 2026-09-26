<p align="center">
  <img src="subnetdesk.svg" width="96" height="96" alt="SubnetDesk">
</p>

<h1 align="center">SubnetDesk</h1>

<p align="center">
  Удалённый рабочий стол внутри локальной сети или VPN
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0--only-blue?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64, arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/subnetdesk
```

## Возможности

[SubnetDesk](https://github.com/zibo-chen/SubnetDesk) — форк RustDesk, из
которого убран публичный контур: нет ни rendezvous-сервера для поиска узлов,
ни relay-сервера для проброса трафика через интернет. Подключение выполняется
по адресу узла внутри локальной сети или VPN, поэтому сессия физически не
выходит за пределы вашей сети.

Возможности те же, что у RustDesk: удалённый рабочий стол, передача файлов,
переброс портов, чат, несколько мониторов, вход по паролю или по системной
учётной записи.

## Состав пакета

| Путь | Назначение |
|:--|:--|
| `/usr/bin/subnetdesk` | ссылка на исполняемый файл приложения |
| `/usr/share/subnetdesk/` | Flutter-бандл: бинарник, `lib/`, `data/` |
| `/usr/share/applications/subnetdesk.desktop` | пункт меню |
| `/usr/share/applications/subnetdesk-link.desktop` | обработчик ссылок `subnetdesk:` |
| `/usr/lib/systemd/system/subnetdesk.service` | служба входящих подключений |
| `/etc/pam.d/subnetdesk` | проверка пароля системной учётной записи |
| `/etc/subnetdesk/xorg.conf` | описание виртуального дисплея для headless-сессии |
| `/etc/subnetdesk/startwm.sh` | запуск оконного менеджера в headless-сессии |

Файлы в `/etc` объявлены в рецепте как конфигурационные (`backup=`), но Stapler
v0.1.1 не переносит это объявление в RPM-флаг `%config` — проверено на готовом
артефакте, `rpm -qp --queryformat '[%{FILENAMES} %{FILEFLAGS}\n]'` показывает
`0`. Поэтому при обновлении пакета ваши правки в этих трёх файлах будут
заменены: сохраните копию, если меняли их.

## Технические детали

### Служба включается при установке

Пакет включает и запускает `subnetdesk.service` при **первой** установке — так
же, как официальные `.deb` и `.rpm` самого SubnetDesk. Без службы машина может
только управлять другими, но не быть управляемой.

`systemctl preset` здесь не подходит: политика пресетов ALT заканчивается
правилом `disable *`, и служба осталась бы выключенной. При обновлении пакета
служба заново не включается: отключённая останется отключённой, а работающая
будет перезапущена на новый бинарник (`try-restart`).

Если входящие подключения не нужны:

```bash
sudo systemctl disable --now subnetdesk.service
```

Чтобы этой машиной можно было управлять, задайте постоянный пароль в
настройках приложения: без него каждое подключение требует подтверждения на
стороне хоста.

### PAM переписан под ALT

Это единственный файл payload, который пакет заменяет. Upstream поставляет
debian-вариант `/etc/pam.d/subnetdesk` с `@include common-auth` (и отдельный
suse-вариант с `include common-auth`), а в его `.rpm` файла PAM нет вовсе. На
ALT сервисов `common-*` не существует, поэтому `pam_start` завершился бы
ошибкой и вход по системной учётной записи был бы невозможен. ALT собирает
стек в `system-auth` — ровно так же, как `/etc/pam.d/polkit-1` и другие
системные сервисы ALT.

### Wayland и X11

На X11 всё работает без дополнительных условий: захват экрана идёт через
`libxcb`, а нажатия и движения мыши вводятся через `libxdo` (пакет `xdotool`).

На Wayland захват экрана идёт через `xdg-desktop-portal` и GStreamer-элемент
`pipewiresrc` из пакета `pipewire`. Первый объявлен как рекомендуемый, второй —
как обязательная зависимость: без плагина PipeWire Wayland-сессию нельзя
захватить в принципе. Если портал не отвечает, приложение само предлагает:

```bash
systemctl --user restart xdg-desktop-portal
```

### Зависимости, которых не видит линковщик

`auto_req` собирает зависимости из `DT_NEEDED` payload, поэтому GTK 3, GLib,
Pango, Cairo, GStreamer, PulseAudio, PAM и X11 попадают в пакет сами. Явно
объявлено то, что приложение загружает через `dlopen` или запускает как
подпроцесс: `xdotool` (`libxdo.so.3`), `libva` (аппаратные кодеки),
`libxkbcommon-x11`, `procps` (`pkill` в `ExecStop` службы и `pgrep` для
определения Wayland), `xrandr` (перечисление режимов дисплея), `xauth` (доступ
к X-дисплею пользователя из службы) и `pipewire`.

### Headless-сессия

`/etc/subnetdesk/xorg.conf` описывает дисплей на драйвере `dummy`, который
служба поднимает, когда за машиной никто не вошёл в систему. Для этого нужны
`xorg-server` и `xorg-drv-dummy`; они объявлены как рекомендуемые, потому что
на машине с обычным графическим входом не требуются.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
