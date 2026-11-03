# tmux — `zenide project`: фаззи-прыжок по проектам (одна сессия = один проект).
# `s`         — выбрать проект через fzf и открыть/переключиться в его сессию.
# `s <путь>`  — сразу в конкретный проект.
# Работает и вне tmux (сделает attach), и внутри (switch-client).
s() { "${ZENIDE_ROOT:-$HOME/.config/zenide}/bin/zenide" project "$@"; }
