#!/usr/bin/env bash
# Настоящий попап: история, мышь, cwd и удаление временного сервера.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT
echo 't-terminal: прокрутка попап-терминала'
t_setup
t_load_conf

# Вложенный клиент даёт pty и позволяет послать реальные mouse escape codes.
mkdir -p "$FIX/tmp" "$FIX/work dir"
zt set-environment -g TMPDIR "$FIX/tmp"
zt send-keys -t t: "cd '$FIX/work dir'" Enter
zt new-session -d -s view -x 200 -y 50 "env -u TMUX tmux -L $SOCK attach-session -t t"
zt set -t view status off
for _ in $(seq 1 40); do
    [ -n "$(zt list-clients -t t -F '#{client_name}')" ] && break
    sleep 0.1
done
zt send-keys -t view: C-Space Space
socket=''
for _ in $(seq 1 60); do
    for candidate in "$FIX"/tmp/zenide-terminal.*/tmux; do
        [ -S "$candidate" ] && socket="$candidate"
    done
    [ -n "$socket" ] && tmux -S "$socket" list-clients 2>/dev/null | grep -q . && break
    sleep 0.1
done
if [ -z "$socket" ]; then
    t_fail "попап не запустился: $(zt capture-pane -p -t view:)"
    exit 1
fi
inner() { tmux -S "$socket" "$@"; }
assert_eq 'cwd попапа совпадает с cwd пейна' "$(inner display-message -p '#{pane_current_path}')" "$(cd "$FIX/work dir" && pwd -P)"
assert_eq 'история наследует лимит проекта' "$(inner show -gv history-limit)" "$(zt show -gv history-limit)"

zt send-keys -t view: -l 'printf "%s\n" "$TMUX" > ../outer-tmux; seq 1 200'
zt send-keys -t view: Enter
for _ in $(seq 1 40); do
    inner capture-pane -p | grep -qx 200 && break
    sleep 0.1
done
assert_eq 'команды шелла видят сервер проекта' "$(cat "$FIX/outer-tmux")" "$TMUX"
assert_has 'ранний вывод сохранён в истории' "$(inner capture-pane -p -S -)" $'\n1\n2\n'

# Колесо вверх внутри рамки попапа (SGR mouse): проверяем весь маршрут
# терминал → внешний клиент → попап → внутренний copy-mode.
zt send-keys -t view: -l $'\033[<64;100;25M'
for _ in $(seq 1 40); do
    [ "$(inner display-message -p '#{pane_in_mode}')" = 1 ] && break
    sleep 0.1
done
assert_eq 'колесо открывает историю' "$(inner display-message -p '#{pane_in_mode}')" 1
zt send-keys -t view: q
zt send-keys -t view: C-Space '['
sleep 0.2
assert_eq 'C-Space [ открывает историю' "$(inner display-message -p '#{pane_in_mode}')" 1
zt send-keys -t view: g
sleep 0.2
if zt capture-pane -p -t view: | grep -qE '│1 +│'; then
    t_ok 'прокрутка до начала показывает первую строку вывода'
else
    t_fail 'после прокрутки первая строка не видна'
fi
zt send-keys -t view: q
zt send-keys -t view: C-d
for _ in $(seq 1 40); do
    [ ! -d "${socket%/*}" ] && break
    sleep 0.1
done
assert_eq 'закрытие удалило сервер и временный каталог' "$([ -d "${socket%/*}" ] && echo осталось)" ''
assert_eq 'внешняя сессия сохранилась' "$(zt display-message -p -t t: '#{session_name}')" t

# Закрытие рамки снаружи также не должно оставлять сервер с шеллом.
socket=''
zt send-keys -t view: C-Space Space
for _ in $(seq 1 60); do
    for candidate in "$FIX"/tmp/zenide-terminal.*/tmux; do
        [ -S "$candidate" ] && socket="$candidate"
    done
    [ -n "$socket" ] && inner list-clients 2>/dev/null | grep -q . && break
    sleep 0.1
done
if [ -z "$socket" ]; then
    t_fail 'повторное открытие не запустило попап'
    exit 1
fi
zt display-popup -C -c "$(zt list-clients -t t -F '#{client_name}')"
for _ in $(seq 1 40); do
    [ ! -d "${socket%/*}" ] && break
    sleep 0.1
done
assert_eq 'закрытие рамки удалило временный каталог' "$([ -d "${socket%/*}" ] && echo осталось)" ''
if inner has-session 2>/dev/null; then
    t_fail 'после закрытия рамки остался внутренний сервер'
else
    t_ok 'после закрытия рамки внутренний сервер завершился'
fi
exit "$FAILED"
