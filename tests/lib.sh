#!/usr/bin/env bash
# Хелперы headless-тестов моста.
#
# Принцип: всё крутится на ИЗОЛИРОВАННОМ сокете (`tmux -L zenide-test`), живая
# сессия на сокете default не трогается никогда. Сервер поднимается с
# `-f /dev/null` (чистый), затем конфиг сорсится явно — так опции совпадают с
# продакшеном, но момент загрузки под контролем.
#
# Скрипты моста зовут `tmux` без `-L`, то есть сокет берут из $TMUX. Поэтому
# харнесс выставляет $TMUX на тестовый сервер — иначе скрипты ушли бы в живую
# сессию. Формат $TMUX: <socket_path>,<pid>,<session_index>.
#
set -u

SOCK=zenide-test
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Проверяем текущий checkout; установленный zenide и личные конфиги не нужны.
z() {
    local op="$1"; shift
    if [ "$op" = twins ]; then
        "$REPO_ROOT/modules/keyboard-cyrillic-twins/init.sh" "$@"
    else
        "$REPO_ROOT/bin/zenide" "$op" "$@"
    fi
}

zt() { tmux -L "$SOCK" "$@"; }

# macOS без coreutils: timeout нет, alarm через perl (см. AGENTS.md)
t_timeout() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

# ── каркас теста ───────────────────────────────────────
FIX=""
t_setup() {
    FIX="$(mktemp -d "${TMPDIR:-/tmp}/zenide-fix.XXXXXX")"
    export HOME="$FIX/home"
    export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
    export XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
    export ZENIDE_ROOT="$REPO_ROOT" ZENIDE_PROFILE="$HOME/profile"
    mkdir -p "$XDG_CONFIG_HOME" "$ZENIDE_PROFILE"
    cp "$REPO_ROOT"/profile/*.conf "$ZENIDE_PROFILE/"
    cp "$REPO_ROOT/VERSION" "$ZENIDE_PROFILE/.zenide-version"
    ln -s "$REPO_ROOT" "$XDG_CONFIG_HOME/zenide"
    ln -s "$REPO_ROOT/ide/tmux" "$XDG_CONFIG_HOME/tmux"
    ln -s "$REPO_ROOT/ide/helix" "$XDG_CONFIG_HOME/helix"
    ln -s "$ZENIDE_PROFILE" "$XDG_CONFIG_HOME/zenide-profile"
    git init -q "$FIX"
    printf 'alpha\nbravo\ncharlie\ndelta\n'        > "$FIX/a.txt"
    printf 'one\ntwo\nthree\nfour\nfive\nsix\n'    > "$FIX/b.txt"
    mkdir -p "$FIX/deep/nested"
    printf 'needle here\n'                          > "$FIX/deep/nested/c.txt"
    git -C "$FIX" add -A
    git -C "$FIX" -c user.email=t@example -c user.name=test commit -qm init

    zt kill-server 2>/dev/null
    # -f /dev/null: чистый сервер, конфиг грузим сами
    zt -f /dev/null new-session -d -s t -c "$FIX" -x 200 -y 50 "/bin/bash --noprofile --norc" || exit 1
    zt set -g default-shell /bin/bash || exit 1
    local address
    address="$(zt display-message -p '#{socket_path},#{pid},#{session_id}')" || exit 1
    [ -n "$address" ] || exit 1
    export TMUX="${address//\$/}"
    unset TMUX_PANE
}

# Конфиг продакшена, но без хуков: хук session-window-changed впрыскивает
# :reload-all и съедает @hx_skip_reload — в юнит-тестах это недетерминизм.
# Тест протокола включает нужный хук обратно сам.
t_load_conf() {
    zt source-file "$REPO_ROOT/ide/tmux/tmux.conf" || exit 1
    zt set-hook -gu session-window-changed 2>/dev/null
    zt set-hook -gu after-select-pane      2>/dev/null
    zt set-hook -gu client-session-changed 2>/dev/null
}

t_teardown() {
    zt kill-server 2>/dev/null
    [ -n "$FIX" ] && rm -rf "$FIX"
    unset TMUX
}

# ── helix в окне ───────────────────────────────────────
# Ждём именно статусбар (NOR), а не фиксированный sleep: старт hx плавает
# из-за LSP и прогрева ФС.
t_hx_start() { # t_hx_start [файл]
    local f="${1:-a.txt}"
    zt new-window -t t -n hx -c "$FIX" hx "$f"
    for _ in $(seq 1 60); do
        t_pane hx | grep -q 'NOR' && return 0
        sleep 0.25
    done
    printf 'helix не поднялся за 15с\n' >&2
    return 1
}

# Пейн-таргет: '=имя' для пейна НЕ работает (грабля из AGENTS.md) — берём
# window_id и даём его как таргет, он разрешается в активный пейн окна.
t_win() { zt list-windows -t t -F '#{window_id} #{window_name}' | awk -v n="$1" '$2 == n { print $1; exit }'; }
t_pane() { local w; w="$(t_win "$1")"; [ -n "$w" ] && zt capture-pane -p -t "$w"; }
t_statusline() { t_pane "$1" | grep -E '^ *(NOR|INS|SEL) ' | tail -1; }

# ── ассерты ────────────────────────────────────────────
# Выставляется здесь, читается во включающих файлах (`exit $FAILED`). export —
# не для подпроцессов, а чтобы линтер видел, что переменную используют снаружи.
export FAILED=0
t_ok()   { printf '  ok   %s\n' "$1"; }
t_fail() { printf '  FAIL %s\n' "$1" >&2; FAILED=1; }

assert_has() { # assert_has <имя> <текст> <подстрока>
    case "$2" in
    *"$3"*) t_ok "$1" ;;
    *)      t_fail "$1: не нашёл «$3» в: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-200)" ;;
    esac
}
assert_not_has() {
    case "$2" in
    *"$3"*) t_fail "$1: нашёл «$3», а не должен" ;;
    *)      t_ok "$1" ;;
    esac
}
assert_eq() {
    [ "$2" = "$3" ] && t_ok "$1" || t_fail "$1: ожидал «$3», получил «$2»"
}
