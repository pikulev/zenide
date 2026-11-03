#!/usr/bin/env sh
# Запуск адресуемого экземпляра yazi; jump посылает reveal без перезапуска.
yazi_start() (
    root="$1"
    id="$(date +%s)$$"
    win="$(tmux new-window -P -F '#{window_id}' -n yazi -c "$root" \
        -e "YAZI_ROOT=$root" yazi --client-id "$id" "$2")" || return
    tmux set -w -t "$win" @zenide_yazi_id "$id"
)
