<p align="center">
  <img src="openwhispr.png" width="96" height="96" alt="OpenWhispr">
</p>

<h1 align="center">OpenWhispr</h1>

<p align="center">
  Приложение для голосового ввода с открытым исходным кодом
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-brightgreen?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64-2ea043?style=for-the-badge" alt="amd64">
</p>

---

## Установка

```bash
sudo stplr install nivora/openwhispr
```

## Возможности

[OpenWhispr](https://openwhispr.com/) — диктовка речи в текст на базе
whisper.cpp, вставляющая распознанный текст в любое активное приложение.
Поддерживает локальные модели (whisper.cpp, sherpa-onnx) и облачные (BYOK —
свой ключ API), заметки со встреч с диаризацией и AI-чат.

## Настройка после установки

Вставка текста в другие приложения работает через `ydotool`, а не напрямую —
это отдельный демон с доступом к `/dev/uinput`, не запускающийся сам по себе:

```bash
sudo usermod -aG input "$USER"
systemctl --user enable --now ydotool.service
```

Группа `input` требуется правилом udev самого пакета `ydotool`
(`80-uinput.rules`) — без неё демон не получит доступ к `/dev/uinput`.
Изменение группы применяется после перезахода в сеанс.

Захват системного звука (для транскрибации из других приложений) использует
`libpipewire`.

## Технические детали

Пакет извлекает официальный `.deb`-релиз OpenWhispr без изменений кода.
Bundled-рантайм включает собственные сборки whisper.cpp, llama.cpp,
sherpa-onnx и onnxruntime — отдельные системные зависимости для них не
нужны, `auto_req` отключён намеренно.

`ydotool` и `libpipewire` объявлены жёсткими зависимостями, а не
опциональными: это `Depends` самого upstream DEB, а не то, что добавлено
Nivora — без них базовая функция приложения (вставка распознанного текста)
не работает.

Electron-песочница (`chrome-sandbox`) получает setuid-бит `4755` только если
ядро не поддерживает непривилегированные user namespaces — как и в остальных
Electron-пакетах каталога. Собственный launcher upstream (`open-whispr`)
дополнительно форсирует X11 под Wayland-сессией: позиционирование
оверлея диктовки требует настоящего X11, а не только XWayland.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
