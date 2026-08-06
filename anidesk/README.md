<p align="center">
  <img src="anidesk.png" width="96" height="96" alt="AniDesk">
</p>

<h1 align="center">AniDesk</h1>

<p align="center">
  Неофициальный desktop-клиент Anixart
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--only-blue?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64-2ea043?style=for-the-badge" alt="amd64">
</p>

---

## Установка

```bash
sudo stplr install nivora/anidesk
```

## Возможности

AniDesk — неофициальный Electron desktop-клиент [Anixart](https://github.com/theDesConnet/AniDesk)
с поддержкой аккаунта, встроенным видеоплеером и Anime4K-апскейлом через
WebGPU.

## Технические детали

Пакет собирается из официального upstream-релиза `theDesConnet/AniDesk` без
патчей кода. Electron-песочница (`chrome-sandbox`) при установке получает
setuid-бит `4755` только если ядро не поддерживает непривилегированные user
namespaces — на системах с рабочим `unshare --user` используется обычный
`0755`, и приложение запускается без setuid-обёртки.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
