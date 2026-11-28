# NetBird

NetBird соединяет устройства в частную сеть через WireGuard. Пакет устанавливает консольный клиент `netbird` и службу `netbird.service`.

ALT Linux p11 · x86_64 · aarch64 (предварительная поддержка)

## Установка

Клиент распространяется по лицензии [BSD-3-Clause](https://github.com/netbirdio/netbird/blob/main/LICENSE).

```bash
sudo stplr install nivora/netbird
```

## Первое подключение

При первой установке пакет включает и запускает службу. Чтобы подключиться к NetBird Cloud, выполните команду и откройте ссылку для входа.

```bash
sudo netbird up
```

Для собственного сервера укажите его адрес при подключении.

```bash
sudo netbird up --management-url https://netbird.example.org
```

Команда `netbird status` показывает состояние соединения. Чтобы отключиться, выполните `sudo netbird down`.

Служба хранит профили и ключи в `/var/lib/netbird`. Обновление и обычное удаление пакета сохраняют эти данные. Переменные окружения службы можно задать в `/etc/sysconfig/netbird`. Чтобы применить изменения, выполните `sudo systemctl restart netbird`.

[Документация NetBird](https://docs.netbird.io/) · [Подключение Nivora](../.github/docs/installation.md) · [Каталог приложений](../README.md)
