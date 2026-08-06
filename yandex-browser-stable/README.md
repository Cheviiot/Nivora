<p align="center">
  <img src="https://browser.yandex.ru/apple-touch-icon.png" width="96" height="96" alt="Яндекс Браузер">
</p>

<h1 align="center">Яндекс Браузер</h1>

<p align="center">
  Быстрый и безопасный браузер на основе Chromium
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Custom-lightgrey?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64-2ea043?style=for-the-badge" alt="amd64">
</p>

---

## Установка

```bash
sudo stplr install nivora/yandex-browser-stable
```

## Возможности

Яндекс Браузер объединяет технологии Chromium со встроенным переводом
страниц, защитой, синхронизацией и сервисами Яндекса.

## Технические детали

Пакет собирается из официального stable-репозитория
`repo.yandex.ru/yandex-browser/deb`. Обновления браузера переданы Stapler:
рецепт намеренно не устанавливает upstream-хуки автообновления (`/etc/cron`,
`/etc/xdg/autostart`) — их отсутствие проверяется отдельным тестом.

Canonical desktop-id совпадает с идентификатором окна (`StartupWMClass`) и
интеграцией с XDG Desktop Portal; прежний desktop-id скрыт (`NoDisplay=true`)
и сохранён только для совместимости, чтобы GNOME не показывал launcher и
запущенное окно как два разных приложения.

При установке скрипт `update_codecs` подтягивает дополнительные медиакодеки
(`libffmpeg.so`), которых нет в базовой сборке.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
