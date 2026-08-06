<h1 align="center">Vintner</h1>

<p align="center">
  Кросс-компиляция с реальным MSVC на Linux через Wine
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-brightgreen?style=for-the-badge" alt="Лицензия"></a>
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-2ea043?style=for-the-badge" alt="amd64, arm64">
</p>

---

## Установка

```bash
sudo stplr install nivora/vintner
```

## Возможности

[Vintner](https://github.com/Cheviiot/vintner) — однобинарный инструмент для
кросс-компиляции с реальным MSVC на Linux через Wine. После `vintner
download`/`vintner install` команды `cl`, `link`, `lib`, `rc`, `midl`, `mc`,
`mt`, `dumpbin`, `msbuild`, `nmake`, `ml`, `ml64`, `armasm`, `armasm64`, `cmd`
и `findstr` работают как обычные команды — без добавления `<dest>/bin/<arch>`
в `PATH` — либо вызываются напрямую как `vintner cl`, `vintner msbuild` и т.д.

Дополнительно поддерживаются:

- сборка настоящих KMDF/UMDF-драйверов через Windows Driver Kit
  (`--with-wdk`);
- устаревший код на D3DX9 через DirectX SDK (`--with-dxsdk`);
- старые `.vcxproj` с закреплённым `PlatformToolset` (v90–v143),
  прозрачно резолвящиеся на единственный установленный компилятор;
- докачка прерванных загрузок и файловая блокировка каталога назначения,
  чтобы параллельные запуски `download`/`install` не повредили дерево файлов;
- `vintner doctor` — диагностика неисправной настройки wine/toolchain.

CLI доступен на английском и русском (`VINTNER_LANG`).

## Технические детали

Пакет устанавливает единственный статический бинарник и регистрирует
автодополнение для bash и zsh через хелпер Stapler `install-completion` —
работает сразу после установки, без ручного
`source <(vintner completion bash)`.

---

<p align="center">
  Часть <a href="../README.md"><b>Nivora</b></a>
</p>
