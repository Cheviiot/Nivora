<p align="center">
  <img src="https://parsec.app/favicon.ico" width="96" height="96" alt="Parsec">
</p>

<h1 align="center">Parsec</h1>

<p align="center">
  Клиент удалённого рабочего стола и игрового стриминга с низкой задержкой
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Custom-lightgrey?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64-2ea043?style=for-the-badge" alt="amd64">
</p>

---

## Установка

```bash
sudo stplr install nivora/parsec
```

## Возможности

[Parsec](https://parsec.app/downloads) — проприетарный клиент удалённого
рабочего стола и игрового стриминга с низкой задержкой.

## Технические детали

Пакет переупаковывает официальный DEB, который upstream распространяет для
Ubuntu 22.04 LTS Desktop — отдельного нативного ALT-релиза Parsec не
существует. Зависимости подобраны под ALT-эквиваленты Ubuntu-библиотек, на
которые линкуется бинарник: p11 использует `libavcodec61`, а Sisyphus —
`libavcodec62` через release-specific overrides Stapler.

Upstream URL не содержит номер версии и может быть заменён. Пока Parsec не
публикует неизменяемый официальный URL, Nivora помечает его сборку как
`source-volatile`: checksum защищает текущую загрузку, но старый рецепт может
перестать воспроизводиться после обновления upstream. Ежедневный updater поэтому
сравнивает fingerprint HTTP ETag даже при неизменной версии; при замене payload
он обновляет checksum и повышает `release`.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
