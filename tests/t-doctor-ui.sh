#!/usr/bin/env bash
# Опциональные Pilot-тесты и реальный TUI на изолированном сокете zenide-test.
set -u
. "$(dirname "$0")/lib.sh"

ui_python="${XDG_DATA_HOME:-$HOME/.local/share}/zenide/doctor-venv/bin/python"
if [ ! -x "$ui_python" ]; then ui_python="$REPO_ROOT/.sandbox/doctor-venv/bin/python"; fi
if [ ! -x "$ui_python" ] || ! "$ui_python" -c 'import textual' >/dev/null 2>&1; then
    printf '  skip doctor-ui: установи опциональное окружение, см. docs/install.md\n'
    exit 0
fi
"$ui_python" "$REPO_ROOT/tests/test_doctor_ui.py" || exit 1

trap t_teardown EXIT
t_setup
# Лаунчер берёт Python из XDG_DATA_HOME; среда теста остаётся изолированной.
mkdir -p "$XDG_DATA_HOME/zenide"
ln -s "$(dirname "$(dirname "$ui_python")")" "$XDG_DATA_HOME/zenide/doctor-venv"
zt new-window -t t -n doctor -c "$FIX" "$REPO_ROOT/bin/zenide" doctor --ui
ready=0
for _ in $(seq 1 120); do
    if t_pane doctor | grep -q 'Показано:'; then ready=1; break; fi
    sleep 0.25
done
assert_eq 'Textual запустился в tmux и получил отчёт' "$ready" 1
zt send-keys -t "$(t_win doctor)" C-p
sleep 0.2
assert_has 'фильтр Textual доступен в tmux' "$(t_pane doctor)" 'Только проблемы'
zt send-keys -t "$(t_win doctor)" q
for _ in $(seq 1 40); do
    [ -z "$(t_win doctor)" ] && break
    sleep 0.1
done
assert_eq 'q закрывает диагностическое окно' "$(t_win doctor)" ''

# Сквозной путь: найти проверку → закрыть TUI → открыть её файл через мост.
zt new-window -t t -n doctor -c "$FIX" "$REPO_ROOT/bin/zenide" doctor --ui
for _ in $(seq 1 120); do
    t_pane doctor | grep -q 'Показано:' && break
    sleep 0.25
done
doctor_window="$(t_win doctor)"
if [ -n "$doctor_window" ]; then
    zt send-keys -t "$doctor_window" / 'slot.git_tui'
    for _ in $(seq 1 40); do
        t_pane doctor | grep -q 'Показано: 1/' && break
        sleep 0.1
    done
    zt send-keys -t "$doctor_window" Escape C-o
    for _ in $(seq 1 60); do
        t_statusline hx | grep -q 'modules.conf' && break
        sleep 0.25
    done
    assert_has 'doctor открыл выбранный конфиг в Helix' "$(t_statusline hx)" 'modules.conf'
else
    t_fail 'doctor не запустился для проверки открытия файла'
fi
exit "$FAILED"
