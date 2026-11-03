#!/bin/sh
# Обёртка редактора для tig: "+N файл" → helix.
#
# При `set editor-line-number = yes` tig зовёт редактор как
#     hx-goto.sh +<строка> <файл>     (из diff/stage-вида)
# или просто
#     hx-goto.sh <файл>               (например, из дерева)
#
# helix ждёт `файл:строка`, а не vi-стиль `+строка файл`, — переводим здесь.
# Внутри tmux отдаём файл в УЖЕ работающий hx: один инстанс на проект, фокус
# уезжает в его окно. Вне tmux — обычный блокирующий hx в текущем терминале.
set -u

[ $# -gt 0 ] || exit 0

line=""
if [ "${1#+}" != "$1" ]; then
    line="${1#+}"
    shift
fi
file="${1:-}"
[ -n "$file" ] || exit 0

if [ -n "${TMUX:-}" ]; then
    exec "${ZENIDE_ROOT:-$HOME/.config/zenide}/bin/zenide" open "$file" "$line"
fi

if [ -n "$line" ]; then
    exec hx "$file:$line"
fi
exec hx "$file"
