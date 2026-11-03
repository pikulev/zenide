#!/usr/bin/env bash
# Ядро моста: файл уходит в РАБОТАЮЩИЙ hx, курсор встаёт на нужную строку.
# Это тот самый механизм, который держится на bracketed paste и паузе после
# Escape — ломается молча, глазами не видно. Проверяем по статусбару hx.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT

echo "t-open: открытие файла в работающем hx"
t_setup
t_load_conf
t_hx_start a.txt || exit 1

# ── абсолютный путь + строка ───────────────────────────
z open "$FIX/b.txt" 4
sleep 1
sl="$(t_statusline hx)"
assert_has "открыл b.txt"            "$sl" "b.txt"
assert_has "встал на строку 4"       "$sl" "4:"
# путь релятивизуется к cwd пейна hx — в статусбаре не должно быть /private/tmp
assert_not_has "путь относительный"  "$sl" "$FIX"

# ── относительный путь ─────────────────────────────────
z open "deep/nested/c.txt" 1
sleep 1
sl="$(t_statusline hx)"
assert_has "открыл вложенный файл" "$sl" "c.txt"

# ── буфер реально содержит текст файла, а не текст команды ──
# Известный режим отказа: команда печатается в буфер как текст вместо
# исполнения (ESC склеился со следующим символом → Alt-char).
body="$(t_pane hx)"
assert_not_has "нет «open» текстом в буфере"   "$body" ":open"
assert_not_has "нет «reload» текстом в буфере" "$body" ":reload"
assert_has     "видно содержимое c.txt"        "$body" "needle here"

# ── hx в сессии нет → поднять новое окно с файлом ──────
zt kill-window -t "$(t_win hx)"
sleep 0.3
name="cold' \$(touch COLD_EXECUTED).txt"
printf 'COLD_CONTENT\n' > "$FIX/$name"
z open "$FIX/$name"
sleep 2
assert_has "поднял hx, когда его не было" "$(t_win hx)" "@"
assert_has "новый hx открыл путь с кавычкой и пробелами" "$(t_pane hx)" COLD_CONTENT
[ ! -e "$FIX/COLD_EXECUTED" ] && t_ok "новый hx не исполнил имя файла" || t_fail "имя файла исполнилось"

exit $FAILED
