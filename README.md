# Codex SSH Remote Setup

Практический Codex skill для настройки и восстановления стабильной работы удалённых проектов через SSH. Он предназначен для сценария, где Codex Desktop используется на компьютере B как интерфейс, а файлы, команды, инструменты и новые удалённые задачи должны выполняться и храниться на постоянно включённом компьютере A.

Скилл собран на основе реальной настройки Windows → Tailscale → WSL. В нём сохранены рабочие решения, неудачные подходы, точные симптомы ошибок и безопасные способы проверки каждого уровня соединения.

> Это независимый пользовательский скилл. Ручная работа с внутренними файлами сессий Codex является резервным и версионно-зависимым сценарием.

## Что умеет скилл

- проектировать устойчивое подключение Codex Desktop через SSH;
- настраивать Windows, WSL, Linux, OpenSSH и Tailscale;
- проверять SSH-ключи, `ssh-agent`, `known_hosts` и BatchMode;
- находить ошибки в эффективном конфиге через `ssh -G`;
- диагностировать `Connection failed`, `Connection reset` и нестабильные подключения;
- разбирать `ProxyJump` и `UNKNOWN port 65535`;
- проверять удалённый login shell, `PATH`, версию Codex и запуск app-server;
- объяснять разницу между Remote Control, SSH Connections и `codex resume`;
- разбирать `No chats` при полностью доступных удалённых файлах;
- учитывать раздельные Codex home и индексы задач Windows/WSL;
- определять, на каком компьютере нужен VPN;
- выбирать между новой удалённой задачей, Hand off и резервной миграцией;
- обнаруживать опасные дубликаты task ID;
- сравнивать две JSONL-сессии без их изменения.

## Рекомендуемая схема

~~~text
Codex Desktop на компьютере B
  -> Windows OpenSSH client
  -> Tailscale или другая доверенная mesh-сеть
  -> sshd внутри WSL/Linux на компьютере A
  -> удалённый login shell
  -> codex app-server на компьютере A
  -> проекты и новые удалённые задачи хранятся на A
~~~

Прямой SSH к WSL/Linux предпочтительнее цепочки Windows SSH → `ProxyJump` → `127.0.0.1` → WSL. Промежуточный Windows-хост добавляет второй SSH-сервер, host key, аккаунт, порт, проброс и дополнительную точку отказа.

## Когда применять

Скилл должен выбираться агентом для запросов, содержащих темы и симптомы:

- Codex over SSH, Remote Connections или удалённый проект;
- **Settings / Connections / SSH**;
- компьютер A, компьютер B или always-on host;
- Windows, WSL, Linux, Tailscale, mesh VPN;
- OpenSSH Server, `sshd`, SSH key, `ssh-agent`;
- `Connection failed`, `Connection reset`, connection flapping;
- `ProxyJump` или `UNKNOWN port 65535`;
- `codex: command not found` в удалённом shell;
- app-server не запускается;
- несовместимый `config.toml` или `service_tier`;
- файлы видны, но отображается `No chats`;
- разные хранилища задач Windows и WSL;
- Hand off отклоняет projectless-задачу;
- перенос локального чата на другой компьютер;
- задача появляется и исчезает из-за одинакового ID;
- проверка сохранности перенесённой JSONL-сессии;
- вопрос, где должен работать VPN.

Для обычных SSH-задач, не связанных с Codex, этот скилл не предназначен.

## Установка

### Через Codex

Попросите встроенный установщик загрузить скилл из GitHub:

~~~text
Use $skill-installer to install the skill from
https://github.com/xbrrr/codex-ssh-remote-skill
~~~

### Вручную

Codex загружает пользовательские скиллы из `$HOME/.agents/skills`.

Linux или WSL:

~~~bash
mkdir -p "$HOME/.agents/skills"
git clone https://github.com/xbrrr/codex-ssh-remote-skill.git \
  "$HOME/.agents/skills/codex-ssh-remote-skill"
~~~

Windows PowerShell:

~~~powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.agents\skills" | Out-Null
git clone https://github.com/xbrrr/codex-ssh-remote-skill.git `
  "$env:USERPROFILE\.agents\skills\codex-ssh-remote-skill"
~~~

Если Codex Desktop подключается по SSH, установите скилл на удалённом хосте под пользователем, от которого запускается app-server. Для локальных задач установите его также на локальном компьютере.

Codex обычно обнаруживает изменения автоматически. Если скилл не появился, перезапустите приложение.

## Использование

Явный вызов:

~~~text
Use $codex-ssh-remote-skill to diagnose why the Codex SSH connection
computer-a disconnects before app-server starts.
~~~

Примеры запросов:

- «Настрой стабильное подключение Codex Desktop с Windows B к WSL на компьютере A через Tailscale».
- «Проверь всю цепочку SSH и не проси перезапускать Codex, пока CLI-проверки не пройдут».
- «Разбери Connection closed by UNKNOWN port 65535».
- «Файлы удалённого проекта видны, но там No chats».
- «Безопасно перенеси projectless-чат на удалённый компьютер».
- «Определи, где нужен VPN при работе Codex через SSH».

## Как проходит диагностика

Скилл проверяет цепочку по уровням и останавливается на первом сломанном:

1. Удалённый адрес и порт доступны с компьютера B.
2. `ssh -G` разрешает алиас в ожидаемые host, port, user, identity и proxy.
3. BatchMode SSH подключается без пароля и passphrase prompt.
4. Неинтерактивный удалённый login shell находит `codex`.
5. Удалённая версия Codex запускает app-server и читает свой конфиг.
6. Codex Desktop сохраняет SSH-подключение и папку проекта.
7. Тестовая задача действительно выполняет команды на компьютере A.
8. Повторный запрос работает спустя несколько минут и после повторного открытия проекта.

Главное правило: не перезапускать приложение снова и снова, пока первые пять проверок не проходят из терминала.

## Диагностические инструменты

### Windows-клиент

~~~powershell
.\scripts\diagnose-codex-ssh.ps1 -HostAlias computer-a
~~~

Расширенная трассировка:

~~~powershell
.\scripts\diagnose-codex-ssh.ps1 `
  -HostAlias computer-a `
  -IncludeVerboseSsh
~~~

Скрипт работает в режиме read-only и проверяет эффективный SSH-конфиг, ключи, BatchMode, удалённый `codex --version` и app-server.

### WSL-сервер

Сначала изучите параметры:

~~~bash
./scripts/setup-wsl-sshd.sh --help
~~~

Пример:

~~~bash
sudo ./scripts/setup-wsl-sshd.sh \
  --listen-address <TAILSCALE_IP_WSL> \
  --port <SSH_PORT> \
  --user <WSL_USER> \
  --public-key-file <PUBLIC_KEY_FILE>
~~~

Скрипт рассчитан на Debian/Ubuntu в WSL. Он устанавливает OpenSSH Server, добавляет публичный ключ, создаёт hardened drop-in, отключает парольную авторизацию, проверяет `sshd -t` и откатывает невалидную конфигурацию. Приватный ключ ему передавать нельзя.

### Проверка перенесённой сессии

~~~bash
python3 scripts/verify-session-clone.py source.jsonl destination.jsonl
~~~

Если перенесённая задача уже была продолжена:

~~~bash
python3 scripts/verify-session-clone.py \
  --allow-clone-tail \
  source.jsonl destination.jsonl
~~~

Проверка read-only и сравнивает модельно-значимую структуру файлов. Она не делает ручное копирование официальным способом миграции.

## Частые ошибки

| Ошибка или симптом | Вероятная причина |
|---|---|
| `Add-WindowsCapability ... requires elevation` | PowerShell запущен без прав администратора |
| служба `sshd` не найдена | OpenSSH Server не установился после предыдущей ошибки |
| правильный пароль не принимается | перепутаны Microsoft login, локальный SSH user, PIN и пароль |
| `Host key verification failed` | endpoint не подтверждён или осталась старая запись в `known_hosts` |
| <code>Bad configuration option: &#96;r&#96;n</code> | PowerShell-команда записала escape-последовательность как текст |
| `kex_exchange_identification: Connection reset` | listener или proxy закрыл соединение до авторизации |
| `Connection closed by UNKNOWN port 65535` | сломался stdio-forward канала `ProxyJump`; порт 65535 настраивать не нужно |
| `codex: command not found` | удалённый login shell имеет другой `PATH` |
| `unknown variant priority, expected fast or flex` | удалённый Codex старее читаемой конфигурации |
| `No chats` при доступных файлах | проект и индекс задач различаются либо Windows/WSL читают разные Codex home |
| `stream disconnected ... codex/responses` | app-server на A потерял исходящий доступ или авторизацию |

Полная карта ошибок и проверок: [references/troubleshooting.md](references/troubleshooting.md).

## Чаты и перенос контекста

Скилл различает три сценария:

1. **Новая работа.** Создать задачу в сохранённом удалённом проекте. Команды, файлы и новая задача относятся к компьютеру A.
2. **Задача Git-проекта.** Использовать штатный Hand off при совпадающем репозитории и подкаталоге.
3. **Projectless-задача.** Hand off может быть недоступен. Сначала сделать резервные копии и прочитать [references/chat-portability.md](references/chat-portability.md).

Папка проекта не является папкой с чатами. Windows Codex и WSL Codex на одном компьютере также могут использовать разные каталоги данных.

Нельзя оставлять один вручную скопированный task ID активным на двух хостах. Индекс может считать записи дубликатами, из-за чего задача будет появляться и исчезать.

## Структура

| Файл | Назначение |
|---|---|
| [SKILL.md](SKILL.md) | основной workflow и поисковое описание скилла |
| [agents/openai.yaml](agents/openai.yaml) | отображение скилла в интерфейсе |
| [references/windows-wsl-setup.md](references/windows-wsl-setup.md) | настройка Windows B → WSL A |
| [references/troubleshooting.md](references/troubleshooting.md) | карта ошибок и evidence-first диагностика |
| [references/chat-portability.md](references/chat-portability.md) | Hand off, видимость и миграция задач |
| [scripts/diagnose-codex-ssh.ps1](scripts/diagnose-codex-ssh.ps1) | read-only диагностика Windows-клиента |
| [scripts/setup-wsl-sshd.sh](scripts/setup-wsl-sshd.sh) | настройка sshd в WSL |
| [scripts/verify-session-clone.py](scripts/verify-session-clone.py) | сравнение JSONL-сессий |

## Безопасность

- не публикуйте приватные ключи, `auth.json`, токены, cookies и несанитизированные логи;
- не открывайте Codex app-server напрямую в локальную сеть или интернет;
- используйте SSH через доверенную сеть или mesh;
- сначала подтвердите вход по ключу, затем отключайте пароль;
- сохраняйте резервные копии SSH-конфига, `known_hosts` и индексов Codex;
- не меняйте одновременно порт, ключ, пользователя, proxy и listener;
- не копируйте активную сессию, пока одна из сторон может продолжать запись.

## Проверка качества

Скилл прошёл:

- structural validation;
- синтаксическую проверку Bash, Python и PowerShell;
- проверку на персональные IP, логины, ключи, отпечатки и токены;
- проверку JSONL-сессии против самой себя;
- проверку исходной сессии против перенесённой и продолженной копии;
- независимый forward-test реального `ProxyJump`-сбоя.

## Официальная документация

- [Build skills](https://learn.chatgpt.com/docs/build-skills)
- [Remote connections](https://learn.chatgpt.com/docs/remote-connections)
