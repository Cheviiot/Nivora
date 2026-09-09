<p align="center">
  <img src="https://raw.githubusercontent.com/armbian/imager/main/public/armbian-icon.png" width="96" height="96" alt="Armbian Imager">
</p>

<h1 align="center">Armbian Imager</h1>

<p align="center">
  Официальная запись образов Armbian на SD-карты и USB-накопители
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-GPL--2.0--or--later-blue?style=for-the-badge" alt="Лицензия">
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64 и arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/armbian-imager
```

## Возможности

[Armbian Imager](https://github.com/armbian/imager) — официальная графическая
утилита проекта Armbian. Она помогает выбрать, загрузить и записать образ ОС на
SD-карту или USB-накопитель.

## Технические детали

Nivora переупаковывает официальные `.deb` релиза `2.0.4` для `amd64` и
`arm64`, не изменяя исполняемый файл. Доступ к накопителю выполняется через
UDisks2 и Polkit; для обнаружения устройств используются `lsblk` и `findmnt`.
Встроенный updater upstream включается только в AppImage и поэтому в этом
пакете не перехватывает системные обновления.

> [!WARNING]
> Запись образа уничтожает прежние данные на выбранном накопителе. Перед
> подтверждением внимательно проверьте модель и размер устройства.

Исходные файлы закреплены SHA-256. Полный запуск с реальной записью носителя не
входит в автоматический smoke-тест, поскольку это разрушительная операция.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
