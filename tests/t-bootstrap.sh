#!/usr/bin/env bash
# Миграция шелла личным macOS-bootstrap: временный HOME, без сети и пакетов.
set -u
. "$(dirname "$0")/lib.sh"

echo "t-bootstrap: миграция .zshrc"
if [ "$(uname -s)" != Darwin ]; then
    echo "  skip личный bootstrap предназначен для macOS"
    exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zenide-bootstrap.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
CLONE="$WORK/clone moved"
MOCK="$WORK/bin"
mkdir -p "$CLONE/shell/theme" "$MOCK"
cp "$REPO_ROOT/bootstrap.sh" "$CLONE/"
touch "$CLONE/shell/theme/ultima.zsh-theme"
cat > "$CLONE/shell/zshrc.sh" <<'EOF'
printf 'loaded\n' >> "$HOME/loads"
EOF

# Подменяем только внешние шаги. Исполняется настоящий bootstrap целиком,
# а его .zshrc затем загружается настоящим zsh.
cat > "$CLONE/install.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
[ "${ZENIDE_TEST_INSTALL_FAIL:-0}" = 0 ] || exit 17
printf '%s\n' "$@" > "$HOME/install-args"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$config"
ln -sfn "$PWD" "$config/zenide"
EOF
cat > "$MOCK/brew" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --prefix ]; then printf '%s\n' "$HOME/no-brew"; fi
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$MOCK/mise"
cp "$MOCK/mise" "$MOCK/rustup"
cat > "$MOCK/curl" <<'EOF'
#!/usr/bin/env bash
touch "$HOME/unexpected-network"
exit 99
EOF
cp "$MOCK/curl" "$MOCK/git"
export ZENIDE_TEST_SED="$(command -v sed)"
cat > "$MOCK/sed" <<'EOF'
#!/usr/bin/env bash
[ "${ZENIDE_TEST_SED_FAIL:-0}" = 0 ] || exit 17
exec "$ZENIDE_TEST_SED" "$@"
EOF
chmod +x "$CLONE/install.sh" "$MOCK"/*
export PATH="$MOCK:$PATH"
unset XDG_CONFIG_HOME ZSH_CUSTOM ZENIDE_TEST_INSTALL_FAIL ZENIDE_TEST_SED_FAIL

setup_home() {
    H="$WORK/$1"
    mkdir -p "$H/.oh-my-zsh/themes" "$H/.oh-my-zsh/custom/plugins/forgit" "$H/.cargo/bin"
    ln -s "$MOCK/rustup" "$H/.cargo/bin/rustup"
}
run() { HOME="$H" /bin/bash "$CLONE/bootstrap.sh" > "$H/output" 2>&1; }
check_shell() {
    if HOME="$H" /bin/zsh -efc 'source "$HOME/.zshrc"'; then
        t_ok "$1: .zshrc загружается"
    else
        t_fail "$1: ошибка загрузки .zshrc"
    fi
    assert_eq "$1: конфиг загружен один раз" "$(cat "$H/loads" 2>/dev/null)" loaded
    [ ! -e "$H/unexpected-network" ] && t_ok "$1: сетевых шагов нет" \
        || t_fail "$1: неожиданный сетевой шаг"
}
check_repeat() {
    local before
    before="$(shasum "$H/.zshrc")"
    run || t_fail "повторный bootstrap завершился с ошибкой"
    assert_eq "повторный запуск не меняет .zshrc" "$(shasum "$H/.zshrc")" "$before"
}

setup_home fresh
run || t_fail "установка с пустым HOME"
check_shell "новый .zshrc"
check_repeat
assert_eq "bootstrap выбирает все конфиги" "$(cat "$H/install-args")" \
    $'--apply\n--with\nall,git,mise,prettier'

# Оба вида присваивания должны обновиться на месте, без второго source.
for declaration in 'SHELL_CONFIG_ROOT=' '  export SHELL_CONFIG_ROOT='; do
    setup_home "assignment-${#declaration}"
    printf '# личное\n%s~/old/shell\nsource "$SHELL_CONFIG_ROOT/zshrc.sh"\nKEEP_ME=yes\n' \
        "$declaration" > "$H/.zshrc"
    run || t_fail "миграция $declaration"
    check_shell "$declaration"
    assert_eq "остальные строки и вид присваивания сохранены" "$(cat "$H/.zshrc")" \
        "$(printf '# личное\n%s"${XDG_CONFIG_HOME:-$HOME/.config}/zenide/shell"\nsource "$SHELL_CONFIG_ROOT/zshrc.sh"\nKEEP_ME=yes' "$declaration")"
    check_repeat
done

# Цепочка из относительной и абсолютной ссылки: обе должны пережить sed -i.
setup_home symlink
mkdir -p "$H/dotfiles"
printf 'SHELL_CONFIG_ROOT=~/old/shell\nsource "$SHELL_CONFIG_ROOT/zshrc.sh"\n' > "$H/dotfiles/zshrc"
chmod 600 "$H/dotfiles/zshrc"
ln -s "$H/dotfiles/zshrc" "$H/dotfiles/current"
ln -s dotfiles/current "$H/.zshrc"
run || t_fail "миграция симлинка"
check_shell "симлинк"
assert_eq "внешний симлинк сохранён" "$(readlink "$H/.zshrc")" dotfiles/current
assert_eq "внутренний симлинк сохранён" "$(readlink "$H/dotfiles/current")" "$H/dotfiles/zshrc"
assert_eq "права цели сохранены" "$(stat -f %Lp "$H/dotfiles/zshrc")" 600
check_repeat

# XDG нужен и для нового файла, и при замене старого присваивания.
setup_home xdg
export XDG_CONFIG_HOME="$H/custom config"
run || t_fail "новый .zshrc с XDG"
check_shell "XDG: новый файл"
printf 'SHELL_CONFIG_ROOT=~/old/shell\nsource "$SHELL_CONFIG_ROOT/zshrc.sh"\n' > "$H/.zshrc"
rm "$H/loads"
run || t_fail "миграция с XDG"
check_shell "XDG: миграция"
check_repeat
unset XDG_CONFIG_HOME

# Сбой не должен выдавать успех или оставлять испорченную конфигурацию.
setup_home failed-write
printf 'SHELL_CONFIG_ROOT=~/old/shell\nsource "$SHELL_CONFIG_ROOT/zshrc.sh"\n' > "$H/.zshrc"
before="$(shasum "$H/.zshrc")"
if ZENIDE_TEST_SED_FAIL=1 run; then t_fail "ошибка sed скрыта"; else t_ok "ошибка sed завершает bootstrap"; fi
assert_eq "при ошибке sed исходный файл цел" "$(shasum "$H/.zshrc")" "$before"
assert_not_has "нет ложного успеха после ошибки записи" "$(cat "$H/output")" 'Готово.'
if ZENIDE_TEST_INSTALL_FAIL=1 run; then t_fail "ошибка install скрыта"; else t_ok "ошибка install завершает bootstrap"; fi
assert_eq "ошибка install не запускает миграцию" "$(shasum "$H/.zshrc")" "$before"

setup_home broken-link
ln -s missing "$H/.zshrc"
if run; then t_fail "битый симлинк принят"; else t_ok "битый симлинк останавливает bootstrap"; fi
assert_eq "битый симлинк сохранён" "$(readlink "$H/.zshrc")" missing
[ ! -e "$H/missing" ] && t_ok "цель битой ссылки не создана" || t_fail "цель битой ссылки создана"

exit "$FAILED"
