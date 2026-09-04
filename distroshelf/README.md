<p align="center">
  <img src="https://raw.githubusercontent.com/ranfdev/DistroShelf/main/data/icons/hicolor/scalable/apps/com.ranfdev.DistroShelf.svg" width="96" height="96" alt="DistroShelf">
</p>

<h1 align="center">DistroShelf</h1>

<p align="center">
  GTK4-клиент для управления контейнерами Distrobox
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64-2ea043?style=for-the-badge" alt="amd64">
</p>

---

## Установка

```bash
sudo stplr install nivora/distroshelf
```

[Distrobox](https://distrobox.it/) является обязательной зависимостью пакета;
он использует Podman или Docker, а DistroShelf предоставляет графическую
оболочку поверх него.

## Возможности

[DistroShelf](https://github.com/ranfdev/DistroShelf) — графический
интерфейс на GTK4/libadwaita для создания, входа и удаления контейнеров
Distrobox, экспорта приложений и бинарников из контейнера на хост, а также
просмотра логов и состояния каждого контейнера без обращения к терминалу.

Текущий Nivora payload собирается в ALT p11 и динамически связан с его ABI
(включая ICU 74), поэтому рецепт намеренно ограничен ALT Linux. Для Debian,
Ubuntu, Fedora, Arch, openSUSE и Alpine он не объявляет совместимость, пока не
появятся отдельные target-native сборки или полностью переносимый runtime closure.

## Технические детали

Upstream не публикует готовый Linux-релиз DistroShelf — только vendored
source tarball (основной канал распространения — Flathub). Как и
[GitHub Desktop](../github-desktop/README.md), пакет собирается CI Nivora
из исходников на отдельном workflow
(`.github/workflows/distroshelf-linux.yml`) и публикуется в
[собственном релизе Nivora](https://github.com/Cheviiot/Nivora/releases/tag/distroshelf-1.5.2-linux)
— `Staplerfile` только скачивает и переупаковывает готовый результат, как
и любой другой пакет каталога. Никакой компиляции при установке не
происходит.

Сборка идёт в официальном контейнере ветки **ALT p11**, а не Sisyphus,
Fedora или Ubuntu — у них более новый glibc, и собранный там бинарник
не запускается на системах со старым glibc. ALT p11 также не публикует
GTK4-флейвор VTE (`vte3-gtk4`) вообще, поэтому workflow собирает VTE
0.82.1 с `-Dgtk4=true` из исходников и встраивает получившуюся
`libvte-2.91-gtk4.so.0` прямо в пакет (`/usr/lib/distroshelf/`) вместе с
wrapper-скриптом — это единственная bundled-библиотека, всё остальное
(GTK4, libadwaita, glib2, liblz4) — обычные системные зависимости.
Подробности — в
[`.github/docs/maintenance.md`](../.github/docs/maintenance.md#сборка-в-ci-github-desktop-distroshelf).

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
