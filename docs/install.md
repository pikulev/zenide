# Установка

Здесь команды. Что при этом происходит с конфигами и почему именно так —
[onboarding.md](onboarding.md): четыре симлинка и их потребители, роль `ide/`,
граница между `install.sh` и `bootstrap.sh`, механизмы обратимости.

macOS. Ядро (`libexec/`, `ide/tmux`, модули) переносимо на Linux, но
`bootstrap.sh` и TCC-пляски — чисто macOS.

## Только zenide

Склонируй репозиторий и попробуй сетап в отдельном окружении:

```bash
git clone https://github.com/pikulev/zenide.git ~/zenide
cd ~/zenide
./try                           # отдельные HOME/XDG и сокет tmux
```

Для установки поставь зависимости и посмотри план. Без аргументов установщик
не меняет файлы:

```bash
brew bundle --file=Brewfile
./install.sh
```

Если план подходит, примени его:

```bash
./install.sh --apply
```

По умолчанию устанавливается **только ядро**:

| Что | Куда |
|---|---|
| корень репозитория | `~/.config/zenide` |
| `ide/tmux/` | `~/.config/tmux` |
| `bin/zenide` | `~/.local/bin/zenide` |
| якорь личного профиля | `~/.config/zenide-profile` |
| `profile/*.example` | `*.local` в профиле, если ещё нет |

Конфиги остальных инструментов не трогаются, пока не попросишь:

```bash
./install.sh --with helix,yazi --apply   # поимённо
./install.sh --with slot,taste --apply   # слоем (см. ide/LAYERS)
./install.sh --with all --apply          # всё, КРОМЕ global
```

Слои описаны в [`../ide/LAYERS`](../ide/LAYERS): `core` (без него zenide нет),
`contract` (ядру нужна пара настроек), `slot` (интеграция «открыть в hx»),
`taste` (оформление), `global` (`git`, `prettier`, `mise` — меняют поведение
за пределами IDE, поэтому в `all` не входят).

У кого уже есть свой конфиг — замена не нужна: `ide/<тул>/CONTRACT*` содержит
тот минимум, который достаточно врезать в свой файл. Именно его и проверяет
`zenide doctor`.

Существующие файлы не затираются — уезжают в `*.backup.<случайный-id>/value`.

### Откат и обновление

```bash
./install.sh --uninstall        # вернуть всё как было
./install.sh --copy --apply     # копии вместо симлинков
```

`--uninstall` разворачивает журнал в `~/.local/state/zenide/manifest` в
обратном порядке. Неизменённое установленное снимается, исходные бэкапы
возвращаются. Изменённые копии и подменённые пути сохраняются рядом в
`*.saved.<случайный-id>/value`; личные файлы профиля остаются. При ошибке
откат останавливается и сохраняет оставшиеся записи. Детали, включая
повторную установку и старые манифесты — в [onboarding.md](onboarding.md).

`--copy` нужен тем, кого смущает, что симлинк на живой клон делает `git pull`
и `git checkout` изменением боевого конфига. С копиями обновление — явная
команда.

Вне отката: brew-пакеты, oh-my-zsh, TCC-права, побочные эффекты модулей
раскладки.

В конце прогоняется `zenide doctor`: он скажет, чего не хватает и **что
именно** из-за этого не работает. Опциональные тулы можно доставлять по мере
надобности — бинды висят всегда, попап сам подскажет, чего ему не хватило.

Перечитать tmux без перезапуска: `tmux source-file ~/.config/tmux/tmux.conf`
(или `C-Space r`).

### Первое, что захочется поменять

- `profile/theme.conf` — палитра бара и бордеров (по умолчанию Monokai Pro
  Spectrum);
- `profile/projects.conf` — где лежат твои проекты (без него — автодетект
  `~/code`, `~/projects`, `~/src`, `~/dev`, иначе `$HOME`);
- `profile/modules.conf` — слоты (`git_tui=lazygit|gitui|tig`) и модули; оба
  модуля клавиатуры выключены по умолчанию, потому что трогают системную
  раскладку. Без них ничего не ломается.

Личное кладётся рядом в `*.local` (под `.gitignore`): `modules.local`,
`projects.local`, `git.local`. Трекаемые файлы остаются нейтральными, поэтому
`git pull` из апстрима не конфликтует с твоими правками.

Дальше — [extending.md](extending.md).

### Интерактивный doctor (опционально)

Для редких изменений достаточно открыть `modules.local` или другой файл
профиля в редакторе. Textual добавляет поиск по диагностике, фильтр проблем,
инструкции, открытие связанного файла и повторную проверку.

Нужны `uv` и Python ≥ 3.11; обычные `doctor` и `doctor --json` работают без
них. `uv` уже входит в личный `Brewfile.full`; Python при необходимости
устанавливается через mise. Из клона с установленным zenide:

```bash
UV_PROJECT_ENVIRONMENT="${XDG_DATA_HOME:-$HOME/.local/share}/zenide/doctor-venv" \
  uv sync --locked --no-python-downloads --project libexec/zenide/ui
zenide doctor --ui
```

После изменения `uv.lock` повтори синхронизацию. При `--copy` запускай её по
установленной копии: `--project "${XDG_CONFIG_HOME:-$HOME/.config}/zenide/libexec/zenide/ui"`.
Окружение находится вне клона и вне манифеста установщика; запуск TUI ничего
не скачивает. При отсутствии окружения лаунчер показывает инструкцию.

Клавиши: `/` — поиск, `Ctrl-p` — только проблемы, `Ctrl-r` — повторить,
`Ctrl-o` — открыть связанный существующий файл, `Esc` — вернуться к списку,
`q` — выйти. В поле поиска обычные буквы вводятся как текст. Вне tmux файл
открывается в Helix, после выхода проверки повторяются; в tmux интерфейс
закрывается перед передачей файла в работающий редактор.

Для запуска в большом попапе из tmux:

```bash
tmux display-popup -E -w 90% -h 90% \
  '"${XDG_CONFIG_HOME:-$HOME/.config}/zenide/bin/zenide" doctor --ui'
```

Это первая версия: изменение профиля выполняется вручную в редакторе,
установка пакетов — по показанной инструкции. Отсутствующий файл отображается
в подробностях, но кнопка открытия недоступна. Пользовательский стиль —
`doctor.tcss.local` в активном профиле; пример — `profile/doctor.tcss.local.example`.

## Моя машина целиком

```bash
git clone git@github.com:pikulev/zenide.git ~/myconfig
~/myconfig/bootstrap.sh
```

`bootstrap.sh` — личный слой, он идемпотентен и делает всё остальное:

- `brew bundle` по `Brewfile` и `Brewfile.full`;
- oh-my-zsh + тема `ultima` + forgit;
- rust: rustup + компонент `rust-analyzer` (единственный рантайм НЕ под mise —
  тулчейны и компоненты умеет только он);
- fzf key-bindings + completion;
- `./install.sh --apply --with all,git,mise,prettier` (все конфиги, профиль
  и явно выбранные глобальные слои Git, mise и prettier);
- рантаймы и LSP: один `mise install` по `ide/mise/config.toml` (node двух
  версий, pnpm, bun, LSP web-стек, prettier, ruff, ty) + `mise reshim`;
- `~/.zshrc`-бутстрап через `${XDG_CONFIG_HOME:-$HOME/.config}/zenide/shell`:
  имя каталога клона не важно, старый `SHELL_CONFIG_ROOT` обновляется,
  остальные строки и симлинк `.zshrc` сохраняются.

Сетевые и опциональные шаги не валят прогон — падение печатается как `⚠`.

## Осталось руками

GUI и личное автоматизировать нельзя.

1. `exec zsh` — перезапустить шелл.
2. **SSHFS** (yazi, бинд `M`), если нужен маунт хостов:
   - System Settings → Privacy & Security → Files and Folders → Ghostty →
     включить **Network Volumes** (или Full Disk Access) и перезапустить
     ghostty, иначе маунты отвечают «Operation not permitted»;
   - в `~/.ssh/config` (личный, в репозитории его нет) — блок в `Host *`:
     ```
     ControlMaster auto
     ControlPath ~/.ssh/sockets/%r@%h-%p
     ControlPersist 10m
     ServerAliveInterval 30
     ```
3. **git identity.** `ide/git/config` подключает `profile/git.local` — он под
   `.gitignore`. Заполни имя и почту там.

> Значения из `~/.gitconfig` могут переопределять `ide/git/config`.
> Перед переносом проверь `git config --global --list --show-origin`.

## Проверка

```bash
zenide doctor        # слоты, зависимости, требования к соседям, модули
zenide doctor --json # те же проверки, JSON schema_version=1
./tests/run.sh       # headless-тесты моста (изолированный сокет)
hx --health          # LSP по стекам
```

Живость руками: `C-Space ?` (вся шпаргалка), `C-Space f` (переключатель
проектов), `Z` в yazi (zoxide; база наполнится сама по мере `cd`).

Тесты doctor: `./tests/run.sh doctor doctor-ui`. JSON проверяется стандартным
Python; UI — Pilot и реальным пейном на сокете `zenide-test`. При отсутствии
опционального окружения UI-тесты явно пропускаются. Для разработки можно
установить то же окружение в `$PWD/.sandbox/doctor-venv`: тесты найдут его там.
