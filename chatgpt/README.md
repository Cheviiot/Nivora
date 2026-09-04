<p align="center">
  <img src="chatgpt.png" width="96" height="96" alt="ChatGPT">
</p>

<h1 align="center">ChatGPT</h1>

<p align="center">
  Официальное десктопное приложение ChatGPT со встроенным Codex
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Custom-lightgrey?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64 | arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/chatgpt
```

## Возможности

[ChatGPT for Desktop](https://developers.openai.com/codex/app) — официальное
приложение OpenAI: чат, голос, генерация изображений и встроенная панель
Codex (агент для работы с кодом, обработка ссылок `codex://`). Апстрим
объединил прежнее отдельное приложение Codex с ChatGPT — этот пакет
заменяет собой прежний `codex`, собиравшийся из неофициального
Linux-порта.

## Технические детали

Пакет извлекает официальный `.deb`-релиз OpenAI без изменений кода —
никаких сторонних патчей или пересборки Computer Use, как это было у
прежнего `codex`: панель Codex и Computer Use (`resources/cua_node`)
встроены в апстрим напрямую.

Официальный URL содержит `/latest/` и изменяется на месте. Nivora хранит не
только checksum самого DEB, но и fingerprint его HTTP ETag; ежедневный updater
проверяет его даже при неизменной версии и при замене payload повышает `release`.

На RPM-целях (`ALT`, Fedora, openSUSE) `auto_req=1` включается отдельными
distro-overrides и вычисляет зависимости по фактическому `DT_NEEDED`.
Для DEB/Arch автоматический finder Stapler v0.1.1 не выдаёт переносимых
имён пакетов, поэтому там используются явные `deps_*`. `auto_prov=0` на
всех целях: dirty finder Stapler v0.1.1 не вычисляет provides. Библиотеки,
которые Chromium загружает через `dlopen` (`libnotify`, `libsecret`,
`libXtst`, `libXScrnSaver`), остаются явными зависимостями.

Приложение не содержит setuid-бинарника `chrome-sandbox` — вместо этого
собственный профиль AppArmor (`/etc/apparmor.d/chatgpt`) разрешает
непривилегированные user namespaces для песочницы Electron.

Собранные под musl варианты bundled нативных Node-аддонов
(`node-hid`, `serialport`) удаляются при сборке — они никогда не
загружаются на glibc-системе вроде ALT, но иначе ломают auto_req
неустановимой зависимостью на musl-соглашение об имени `libc.so`.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
