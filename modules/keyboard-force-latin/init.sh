#!/usr/bin/env sh
# Модуль: форс латинской раскладки (ABC) на ЛЮБОЙ переход по tmux.
#
# Зачем модуль, а не часть ядра: нужен только тем, у кого есть нелатинская
# раскладка, и требует macism (macOS). На чистом клоне должен быть выключен.
#
# Регистрирует три хука — они покрывают все переходы: пейн (select-pane ←
# hjkl/клик), окно, сессия. `after-select-pane`, а не `pane-focus-in`:
# последний завязан на focus-события терминала (ненадёжен, идёт не всегда),
# а select-pane детерминирован.
#
# session-window-changed цепляем через -ga: на нём уже висят `zenide reload`
# и refresh-client из ядра, перезатирать их нельзя.
set -u

dir="$(cd "$(dirname "$0")" && pwd)"

tmux set-hook -g  after-select-pane      "run-shell '$dir/abc.sh'"
tmux set-hook -ga session-window-changed "run-shell '$dir/abc.sh'"
tmux set-hook -g  client-session-changed "run-shell '$dir/abc.sh'"
