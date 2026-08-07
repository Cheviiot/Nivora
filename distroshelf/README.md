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

Для реальной работы нужен установленный [Distrobox](https://distrobox.it/)
(и Podman или Docker под ним) — сам DistroShelf лишь графическая оболочка
поверх него.

## Возможности

[DistroShelf](https://github.com/ranfdev/DistroShelf) — графический
интерфейс на GTK4/libadwaita для создания, входа и удаления контейнеров
Distrobox, экспорта приложений и бинарников из контейнера на хост, а также
просмотра логов и состояния каждого контейнера без обращения к терминалу.

## Технические детали

В отличие от остальных пакетов Nivora, DistroShelf собирается из
исходников, а не переупаковывается из готового upstream-бинарника: сам
проект публикует на GitHub Releases только vendored source tarball (`meson
dist` со всеми Cargo-крейтами внутри) — прекомпилированного статического
Linux-релиза upstream не существует, основной канал распространения —
Flathub.

Сборка полностью офлайновая (`meson setup -Doffline=true` + `meson compile`
+ `meson install`) — вся сеть, нужная Cargo, уже упакована в
зафиксированный по SHA-256 tarball, дополнительных запросов к crates.io
на этапе сборки нет. Тулчейн (Rust, meson, ninja, заголовки GTK4/libadwaita/
VTE-GTK4) нужен только для сборки пакета и не входит в его runtime-зависимости.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
