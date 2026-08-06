<p align="center">
  <img src="https://raw.githubusercontent.com/Vencord/Vesktop/main/build/icon.svg" width="96" height="96" alt="Vesktop">
</p>

<h1 align="center">Vesktop</h1>

<p align="center">
  Неофициальный десктопный клиент Discord с улучшенной поддержкой Linux
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64, arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/vesktop
```

## Возможности

[Vesktop](https://vencord.dev/) — неофициальное приложение Discord от команды
Vencord: тот же протокол и учётная запись, что и в официальном клиенте, но
без телеметрии по умолчанию, с более лёгким Electron-рантаймом и встроенным
[Vencord](https://vencord.dev/) (клиентские моды, темы, плагины).

## Почему не официальный Discord

Официальный `.deb`/`.tar.gz` Discord для Linux — не полноценное приложение, а
маленький самообновляющийся bootstrap: реальный Electron-клиент он скачивает
на устройстве пользователя при первом запуске и обновляет себя сам, в обход
Stapler. Зафиксировать SHA-256 для такого payload на этапе сборки рецепта
невозможно — он неизвестен заранее и меняется без участия Nivora, что
противоречит модели доверия репозитория (см. [модель доверия](../.github/docs/security-model.md)).

Vesktop публикует настоящие статические сборки на GitHub Releases
(`amd64`/`arm64` `.deb`), с фиксированной версией и проверяемым SHA-256 —
как и любой другой пакет Nivora.

## Важно

Vesktop — сторонний клиент, подключающийся к официальным серверам Discord.
Использование модифицированных клиентов формально не соответствует условиям
использования Discord, хотя на практике это распространённая и
широко используемая практика (проект имеет более 8000 звёзд на GitHub).
Решение о его использовании — на усмотрение пользователя.

## Технические детали

Пакет извлекает официальный `.deb`-релиз Vesktop без изменений кода.
Electron-песочница (`chrome-sandbox`) получает setuid-бит `4755` только если
ядро не поддерживает непривилегированные user namespaces — в остальных
случаях используется `0755` без setuid. AppArmor-профиль upstream (актуален
только для Ubuntu 24+) не устанавливается — ALT Linux не использует AppArmor.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
