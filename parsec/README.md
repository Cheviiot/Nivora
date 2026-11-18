# Parsec

Клиент удалённого рабочего стола с низкой задержкой. С компьютера на ALT можно подключиться к хосту Parsec на Windows или macOS и управлять им с клавиатуры, мыши или геймпада. [Сайт Parsec](https://parsec.app/downloads)

ALT Linux p11 · x86_64

## Установка

**Лицензия** — проприетарная. При интерактивной сборке Stapler предложит принять [условия Parsec](https://parsec.app/terms).

```bash
sudo stplr install nivora/parsec
```

## Запуск

Откройте **Parsec** из меню или выполните `parsecd`, войдите в аккаунт и выберите доступный компьютер.

Если в профиле ещё не выбран режим клавиатуры, Nivora задаёт `client_immersive=2`, чтобы системные сочетания клавиш передавались на хост. Для одного сеанса с локальными сочетаниями выполните `parsecd client_immersive=0`. Команда `PARSEC_NIVORA_IMMERSIVE=0 parsecd` запускает клиент с настройками самого Parsec, включая уже сохранённый выбор. [Параметры Parsec](https://support.parsec.app/hc/en-us/articles/32381443626516-All-Advanced-Configuration-Options)

[Подключение Nivora](../.github/docs/installation.md) · [Каталог приложений](../README.md)
