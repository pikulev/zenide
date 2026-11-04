#!/usr/bin/env bash
# ЛИЧНОЕ развёртывание на новой машине ОДНОЙ командой. Идемпотентен — можно
# гонять повторно. Делает то, что к zenide не относится: brew bundle ·
# oh-my-zsh+тема+forgit · rust (rustup) · fzf-биндинги · рантаймы и LSP
# (mise, после install.sh — ему нужен симлинк ~/.config/mise) · ~/.zshrc.
#
# Симлинки и профиль — НЕ здесь: это ./install.sh, он часть проекта и работает
# сам по себе. Граница такая: install.sh ставит zenide, bootstrap.sh обустраивает
# МОЮ машину (и зовёт install.sh).
#
# Руками остаётся только GUI/личное (TCC для sshfs, ~/.ssh/config) —
# печатается в конце. Сетевые/опциональные шаги не валят весь прогон (см. try()).

set -uo pipefail
cd "$(dirname "$0")" || exit 1
ROOT="$PWD"

step() { printf '\n== %s ==\n' "$1"; }
try()  { "$@" || printf '  ⚠ не удалось: %s\n' "$*"; }

# ── Homebrew (обязателен) ───────────────────────────────────────────────
command -v brew >/dev/null || { echo 'нет Homebrew: https://brew.sh'; exit 1; }

step "brew bundle"
# тап FUSE-T (sshfs) — сторонний, brew требует явного доверия до bundle;
# каски fuse-t попросят sudo-пароль в процессе установки
brew tap  macos-fuse-t/cask 2>/dev/null || true
brew trust macos-fuse-t/cask 2>/dev/null || true
brew bundle --file=./Brewfile          # ядро zenide
brew bundle --file=./Brewfile.full     # личный стек поверх
# сделать только что поставленные mise/uv/fzf видимыми внутри этого скрипта
eval "$(brew shellenv 2>/dev/null)" || true

# ── oh-my-zsh + тема + forgit (zsh.sh сорсит omz при старте — ставим ДО) ──
step "oh-my-zsh + тема ultima + forgit"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    export RUNZSH=no KEEP_ZSHRC=yes CHSH=no
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
        || echo "  ⚠ oh-my-zsh не установился"
    unset RUNZSH KEEP_ZSHRC CHSH
fi
if [ -d "$HOME/.oh-my-zsh/themes" ]; then
    cp "$ROOT/shell/theme/ultima.zsh-theme" "$HOME/.oh-my-zsh/themes/" \
        && echo "  тема ultima скопирована"
fi
FORGIT_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/forgit"
[ -d "$FORGIT_DIR" ] && echo "  forgit уже есть" \
    || try git clone -q https://github.com/wfxr/forgit.git "$FORGIT_DIR"

# ── Rust ────────────────────────────────────────────────────────────────
step "rust (rustup + rust-analyzer)"
if ! command -v rustup >/dev/null && [ ! -x "$HOME/.cargo/bin/rustup" ]; then
    sh -c "$(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs)" -- -y --no-modify-path \
        || echo "  ⚠ rustup не установился"
fi
# шим rust-analyzer есть всегда, а сам компонент — нет (иначе сервер падает)
[ -x "$HOME/.cargo/bin/rustup" ] && try "$HOME/.cargo/bin/rustup" component add rust-analyzer

# ── fzf: key-bindings + completion (parts/fzf.sh сорсит ~/.fzf.zsh) ──────
step "fzf key-bindings + completion"
FZF_INSTALL="$(brew --prefix)/opt/fzf/install"
if [ -x "$FZF_INSTALL" ]; then
    "$FZF_INSTALL" --key-bindings --completion --no-update-rc --no-bash --no-fish 2>/dev/null \
        || try "$FZF_INSTALL" --all --no-update-rc
fi

# ── ssh: каталог сокетов ControlMaster ──────────────────────────────────
step "ssh: каталог сокетов ControlMaster"
mkdir -p ~/.ssh/sockets && chmod 700 ~/.ssh/sockets

# ── zenide: симлинки, профиль, проверка ─────────────────────────────────
# `--apply` здесь осознанно, хотя dry-run — умолчание install.sh: тот
# установщик ПУБЛИЧНЫЙ и ставится поверх чужих конфигов, а запуск личного
# bootstrap.sh и есть согласие. Без флага шаг печатал план среди логов brew
# и уходил, не поставив ни одного симлинка, — на чистой машине «одной
# командой» не срабатывало, а doctor в конце краснел.
# Личная полная установка включает и глобальные слои: Git, рантаймы и
# форматирование. Публичный install.sh по-прежнему выбирает их только явно.
step "установка zenide (./install.sh --apply --with all,git,mise,prettier)"
./install.sh --apply --with all,git,mise,prettier

# ── Рантаймы и LSP (mise) ───────────────────────────────────────────────
# ПОСЛЕ install.sh: список тулов лежит в ide/mise/config.toml, а mise читает
# его только как ~/.config/mise/config.toml — то есть через симлинк, который
# ставится шагом выше. Поэтому doctor внутри install.sh мог пожаловаться на
# пустой mise: к концу этого шага жалоба станет неактуальной.
#
# Один `mise install` вместо цикла по версиям node с npm-глобалами под каждую:
# npm:/pypi:-тулы живут отдельно от активной версии рантайма.
step "рантаймы и LSP (mise)"
if command -v mise >/dev/null; then
    try mise install
    # шимы для свежепоставленных npm:/pypi:-команд (prettier, ruff, ty…):
    # без reshim они есть на диске, но не на PATH
    try mise reshim
    mise ls --current 2>/dev/null | sed 's/^/  /'
else
    echo "  ⚠ mise не на PATH — пропуск (проверь, что brew bundle его поставил)"
fi

# ── ~/.zshrc бутстрап ───────────────────────────────────────────────────
step "~/.zshrc"
if ! grep -q '^SHELL_CONFIG_ROOT=' "$HOME/.zshrc" 2>/dev/null; then
    printf '\nSHELL_CONFIG_ROOT="$HOME/.config/zenide/shell"\n\nsource "$SHELL_CONFIG_ROOT/zshrc.sh"\n' >> "$HOME/.zshrc"
    echo "  бутстрап дописан"
else
    # Якорь установлен выше и не зависит от имени каталога клона. Остальные
    # строки пользовательского .zshrc остаются на месте.
    sed -i '' 's|^SHELL_CONFIG_ROOT=.*$|SHELL_CONFIG_ROOT="$HOME/.config/zenide/shell"|' "$HOME/.zshrc"
    echo "  путь шелла: ~/.config/zenide/shell"
fi
# Затенение конфигов (~/.gitconfig, ~/.tmux.conf) проверяет `zenide doctor`,
# раздел «затенение» — там же сказано, чем именно это грозит. Здесь не дублируем:
# install.sh в конце гоняет doctor.

# ── финал: то, что автоматом нельзя (GUI / личное) ──────────────────────
cat <<'EOF'

════════════════════════════════════════════════════════════════════════
Готово. Осталось РУЧНОЕ (GUI/личное — автоматизировать нельзя):

1. Перезапусти шелл:   exec zsh

2. SSHFS (yazi, бинд M) — если нужен маунт хостов лабы:
   • System Settings → Privacy & Security → Files and Folders →
     Ghostty → включить «Network Volumes» (или Full Disk Access),
     затем перезапустить Ghostty (иначе «Operation not permitted»).
   • В ~/.ssh/config (личный, в репо его нет) добавить в Host *:
       ControlMaster auto
       ControlPath ~/.ssh/sockets/%r@%h-%p
       ControlPersist 10m
       ServerAliveInterval 30

Проверка живости: zenide doctor · hx --health · C-Space f · Z в yazi (zoxide)
════════════════════════════════════════════════════════════════════════
EOF
