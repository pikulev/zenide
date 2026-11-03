#!/usr/bin/env bash
# Внутренний транспорт Helix. Сорсится только четырьмя операциями адаптера.
# pane задаёт вызывающая операция после поиска редактора.
# shellcheck disable=SC2154

hx_quote() {
    # У Helix свои правила: одинарная кавычка удваивается, экспансий нет.
    local value
    value="$(printf '%s' "$1" | sed "s/'/''/g")"
    printf "'%s'" "$value"
}

hx_finish() {
    if [ "${hx_locked:-0}" = 1 ]; then
        tmux wait-for -U "zenide-hx-$pane"
        hx_locked=0
    fi
}

hx_begin() {
    # Один отправитель на пейн. Таймаут не позволяет зависнуть при оборванном
    # процессе; чужую блокировку по таймауту не снимаем.
    perl -e 'alarm 5; exec @ARGV' tmux wait-for -L "zenide-hx-$pane" || return
    hx_locked=1
    trap hx_finish EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    tmux send-keys -t "$pane" Escape || return
    sleep 0.1
}

hx_cmd() {
    # Имена буферов уникальны для процесса, даже между разными сессиями.
    local buffer="zenide-hx-$$"
    tmux send-keys -t "$pane" ':' &&
        printf '%s' "$1" | tmux load-buffer -b "$buffer" - &&
        tmux paste-buffer -d -p -b "$buffer" -t "$pane" &&
        tmux send-keys -t "$pane" Enter
}
