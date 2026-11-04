# Установка

Здесь команды. Что при этом происходит с конфигами и почему именно так —
[onboarding.md](onboarding.md): четыре симлинка и их потребители, роль `ide/`,
граница между `install.sh` и `bootstrap.sh`, механизмы обратимости.

macOS. Ядро (`libexec/`, `ide/tmux`, модули) переносимо на Linux, но
`bootstrap.sh` и TCC-пляски — чисто macOS.

## Только zenide

Если нужен сам сетап, без моего личного окружения:

```bash
git clone https://github.com/pikulev/zenide.git ~/zenide
cd ~/zenide
./try                           # отдельные HOME/XDG и сокет tmux
brew bundle --file=Brewfile     # ядро: ~13 формул
./install.sh                    # план
./install.sh --apply            # применить
```

Без аргументов `install.sh` печатает план и выходит — это умолчание.
`--apply` ставит **только ядро**:

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

> `~/.gitconfig` **перебивает** `ide/git/config`. Если он есть на машине —
> удали или перенеси настройки; `bootstrap.sh` предупредит.

## Проверка

```bash
zenide doctor        # слоты, зависимости, требования к соседям, модули
./tests/run.sh       # headless-тесты моста (изолированный сокет)
hx --health          # LSP по стекам
```

Живость руками: `C-Space ?` (вся шпаргалка), `C-Space f` (переключатель
проектов), `Z` в yazi (zoxide; база наполнится сама по мере `cd`).
