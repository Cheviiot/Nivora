<p align="center">
  <img src="https://happ.su/imgs/apple-touch-icon.png" width="96" height="96" alt="Happ">
</p>

<h1 align="center">Happ</h1>

<p align="center">
  Удобный GUI-прокси-клиент для xray-core
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Custom-lightgrey?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64, arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/happ
```

## Возможности

[Happ](https://happ.su/) — GUI-клиент для xray-core с режимом TUN/VPN через
sing-box, средствами обхода блокировок, импортом QR-кодов и управлением
подписками.

## Технические детали

Пакет ставит и включает systemd-сервис `happd.service`, обеспечивающий
TUN/VPN-режим без ручного запуска демона после установки.

Собственный Qt-рантайм Happ по умолчанию откатывается на generic-тему GNOME,
которая не умеет сообщать текущую системную цветовую схему. Launcher-обёртка
`/usr/bin/happ` явно включает `QT_QPA_PLATFORMTHEME=xdgdesktopportal`, чтобы
приложение читало тёмную/светлую тему через XDG Desktop Portal и подхватывало
её смену на лету, а не оставалось на светлой теме по умолчанию.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
