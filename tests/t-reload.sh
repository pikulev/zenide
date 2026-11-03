#!/usr/bin/env bash
# Перечитывание буфера с диска и протокол @hx_skip_reload.
# Зачем тест: у hx нет autoread, поэтому после правок снаружи (lazygit discard,
# форматтер) буфер показывает старое. А защита от гонки с hx-open держится на
# одной window-опции — если протокол сломать, в буфер падает «reload-all»
# текстом, и это видно только глазами.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT

echo "t-reload: перечитывание с диска и протокол @hx_skip_reload"
t_setup
t_load_conf
t_hx_start b.txt || exit 1
win="$(t_win hx)"

# ── флаг не стоит → буфер должен подхватить правку с диска ──
printf 'CHANGEDBYDISK\nsecond line\n' > "$FIX/b.txt"
z reload "$win"
sleep 1.2
assert_has "подхватил правку с диска" "$(t_pane hx)" "CHANGEDBYDISK"

# ── флаг стоит → reload молчит и снимает флаг ──────────
zt set -w -t "$win" @hx_skip_reload 1
printf 'SECONDCHANGE\n' > "$FIX/b.txt"
z reload "$win"
sleep 0.8
assert_eq  "флаг снят"                  "$(zt show -wv -t "$win" @hx_skip_reload 2>/dev/null)" ""
assert_not_has "правка НЕ подхвачена"   "$(t_pane hx)" "SECONDCHANGE"

# ── открытие в текущем окне не оставляет флаг на будущий переход ──
z open "$FIX/a.txt" 2
sleep 1
assert_eq "в текущем окне флага нет" "$(zt show -wv -t "$win" @hx_skip_reload 2>/dev/null)" ""

# ── буфер чист от текста команд ────────────────────────
assert_not_has "нет «reload-all» текстом" "$(t_pane hx)" "reload-all"

# ── окно без hx → тихий выход ──────────────────────────
zt new-window -t t -n plain -c "$FIX" 'sleep 30'
sleep 0.4
z reload "$(t_win plain)"
assert_eq "в окне без hx выходит с 0" "$?" "0"

# Настоящий переход ставит флаг; подключённый хук его снимает.
z open "$FIX/a.txt" 2
assert_eq "при переходе open ставит флаг" "$(zt show -wv -t "$win" @hx_skip_reload)" 1
z reload "$win"
zt set-hook -g session-window-changed 'run-shell "\"$ZENIDE_ROOT/bin/zenide\" reload #{window_id}"'
z open "$FIX/a.txt" 2
zt select-window -t "$(t_win plain)"
printf 'AFTER_POPUP_OPEN\n' > "$FIX/a.txt"
zt select-window -t "$win"
sleep 0.5
assert_has "после открытия в текущем окне следующий reload работает" "$(t_pane hx)" AFTER_POPUP_OPEN
zt select-window -t "$(t_win plain)"
z open "$FIX/b.txt" 1
sleep 0.3
assert_eq "хук снял флаг после перехода open" "$(zt show -wv -t "$win" @hx_skip_reload 2>/dev/null)" ""

exit $FAILED
