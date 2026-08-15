<p align="center">
  <img src="yandex-music.png" width="96" height="96" alt="Yandex Music">
</p>

<h1 align="center">Yandex Music</h1>

<p align="center">
  Официальный десктопный клиент Яндекс Музыки
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Custom-lightgrey?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64-2ea043?style=for-the-badge" alt="amd64">
</p>

---

## Установка

```bash
sudo stplr install nivora/yandex-music
```

## Возможности

[Yandex Music](https://music.yandex.ru/download/) — официальный десктопный
клиент стримингового сервиса: персональные рекомендации, подборки,
подкасты, аудиокниги и бесконечное радио «Моя волна». Воспроизведение,
коллекция и поиск — в одном окне, без браузера.

## Технические детали

Пакет извлекает официальный `.deb`-релиз Yandex Music без изменений кода.
Каталог `/opt/Яндекс Музыка` (кириллица в оригинальном пути) переносится в
`/opt/YandexMusic`; upstream desktop-id `yandexmusic` и протокол
`x-scheme-handler/yandexmusic` сохранены.

В отличие от остальных Electron-пакетов каталога, здесь `auto_req=1`/
`auto_prov=1` вместо ручных `deps_*` по дистрибутивам — зависимости
резолвятся по конкретным soname (`libgtk-3.so.0()(64bit)` и т.д.), а не по
именам пакетов, которые различаются между ветками ALT и дистрибутивами.
Bundled-либы Chromium (`libffmpeg.so`, `libvulkan.so.1`,
`libvk_swiftshader.so`) в `Requires:` не попадают — проверено
(`rpm -qp --requires`) и установкой в чистых контейнерах ALT p11 и
Sisyphus. Upstream DEB не объявляет `libgbm`/`libasound` в своих
зависимостях, хотя это реальные `DT_NEEDED`-записи бинарника
`yandexmusic` (та же ситуация, что уже встречалась у `vesktop`) —
auto_req подхватывает их сам, без ручного вмешательства.

`resources/app-update.yml` удаляется при сборке: собственный
автообновлятель Electron не нужен под управлением Stapler.

Electron-песочница (`chrome-sandbox`) получает setuid-бит `4755` только если
ядро не поддерживает непривилегированные user namespaces — как и в
остальных Electron-пакетах каталога.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
