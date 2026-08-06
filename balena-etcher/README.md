<p align="center">
  <img src="https://raw.githubusercontent.com/balena-io/etcher/master/assets/icon.png" width="96" height="96" alt="balenaEtcher">
</p>

<h1 align="center">balenaEtcher</h1>

<p align="center">
  Безопасная запись образов на SD-карты и USB-накопители
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue?style=for-the-badge" alt="Лицензия">
  <img src="https://img.shields.io/badge/arch-amd64-2ea043?style=for-the-badge" alt="amd64">
</p>

---

## Установка

```bash
sudo stplr install nivora/balena-etcher
```

## Возможности

balenaEtcher — графическая утилита [balena.io](https://etcher.balena.io/) для
записи образов операционных систем на SD-карты и USB-накопители с проверкой
данных после прошивки.

## Технические детали

Пакет переупаковывает официальный Linux-релиз Electron-приложения без
изменений кода. Как и у других Electron-пакетов Nivora, Electron-песочница
(`chrome-sandbox`) получает setuid-бит `4755` только когда ядро не
поддерживает непривилегированные user namespaces; в остальных случаях
используется обычный `0755` без setuid.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
