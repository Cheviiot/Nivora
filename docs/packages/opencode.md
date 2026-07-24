# OpenCode

Пакет устанавливает официальный Linux desktop-артефакт OpenCode без изменений его кода и ресурсов.

```bash
sudo stplr install nivora/opencode
```

## Запуск

- из меню приложений — `OpenCode`;
- из терминала — `opencode-desktop`.

Команда `opencode-desktop` является прямой ссылкой на upstream-бинарник
`/opt/OpenCode/ai.opencode.desktop`: wrapper, лимиты памяти, GPU-fallback и другие поведенческие
патчи не применяются.
