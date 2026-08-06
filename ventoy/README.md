<p align="center">
  <img src="https://raw.githubusercontent.com/ventoy/Ventoy/master/ICON/logo_128.png" width="96" height="96" alt="Ventoy">
</p>

<h1 align="center">Ventoy</h1>

<p align="center">
  Создание и управление мультизагрузочными USB-накопителями
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-GPL--3.0--only-blue?style=for-the-badge" alt="Лицензия">
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64, arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/ventoy
```

Пакет устанавливает официальный нативный Linux GUI Ventoy и показывает его в
меню приложений под коротким названием **Ventoy**.

## Запуск

```bash
ventoy
```

При запуске Ventoy запрашивает административные права через `pkexec`, потому
что программа размечает накопители и записывает загрузочные структуры
напрямую.

## Важно

- Перед установкой Ventoy внимательно проверьте выбранное устройство.
- Первичная установка стирает данные на выбранном накопителе.
- Обновление уже подготовленного Ventoy-накопителя сохраняет раздел с
  образами, однако резервная копия важных данных всё равно рекомендуется.
- Пакет использует официальный архив upstream и поддерживает `amd64` и
  `arm64`.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
