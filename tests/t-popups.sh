#!/usr/bin/env bash
# Сквозные тесты попапов: ввод в fzf → файл открылся там, где надо.
#
# Долго считалось, что так нельзя: fzf открывает /dev/tty и глохнет на SIGTTIN.
# Это верно только для запуска fzf НАПРЯМУЮ из неинтерактивного процесса.
# Внутри tmux-пейна у fzf есть pty, поэтому попап работает, а `capture-pane`
# показывает его содержимое. Отсюда и эти тесты.
#
# Попап запускается не через `display-popup` (он не раскрывает #{} и усложняет
# таргетинг), а как обычная команда в окне: для самого попапа разницы нет, он
# всё равно видит перед собой pty.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT

echo "t-popups: попапы fzf от ввода до открытого файла"

Z="$REPO_ROOT/bin/zenide"

t_setup

# Фикстура с историей от двух авторов: без неё blame нечего показывать.
# Авторы РАЗНЫХ строк различаются намеренно — иначе не проверить, на какую
# строку blame встал.
cd "$FIX" || exit 1
printf 'export function pay(amount) {\n  return amount * 2;\n}\n' > src.ts
printf '# docs\nneedle_here in docs\nthird line\n' > doc.md
git -C "$FIX" add -A
git -C "$FIX" -c user.email=a@e -c user.name=Alice commit -qm "САМЫЙ-ПЕРВЫЙ"
printf 'export function pay(amount) {\n  return amount * 3;\n}\n\nexport const LATER = 1;\n' > src.ts
git -C "$FIX" add -A
git -C "$FIX" -c user.email=b@e -c user.name=Bob commit -qm "ПОЗЖЕ-ДОБАВИЛ"

W="$(zt list-windows -t t -F '#{window_id}' | head -1)"

# Запустить попап и дождаться готовности. Ждать промпта недостаточно: fzf
# рисует его сразу, а источник (fd, git blame) ещё сыпет данные, и на экране
# `0/0` со спиннером. Поэтому у попапов со СПИСКОМ признак готовности —
# счётчик fzf с непустым левым числом.
popup_list() { # popup_list <подкоманда…>
    zt send-keys -t "$W" "cd '$FIX' && $Z $*" Enter
    for _ in $(seq 1 60); do
        zt capture-pane -p -t "$W" | grep -qE '[1-9][0-9]*/[0-9]+' && return 0
        sleep 0.25
    done
    return 1
}
# У live-grep список пуст, пока не наберёшь запрос: пустой запрос осознанно не
# матчит всё. Поэтому готовность тут — только промпт.
popup_live() { # popup_live <подкоманда…>
    zt send-keys -t "$W" "cd '$FIX' && $Z $*" Enter
    for _ in $(seq 1 60); do
        zt capture-pane -p -t "$W" | grep -q '❯' && return 0
        sleep 0.25
    done
    return 1
}
# Дождаться окна hx и вернуть его статусбар.
hx_status() {
    local w
    for _ in $(seq 1 60); do
        w="$(t_win hx)"
        if [ -n "$w" ]; then
            t_pane hx | grep -q 'NOR' && { t_statusline hx; return 0; }
        fi
        sleep 0.25
    done
    return 1
}
# Дождаться текста на экране окна. Счётчик fzf появляется раньше превью:
# превью рисует delta, и на холодной ФС это заметно дольше.
wait_text() { # wait_text <подстрока> [секунд]
    local pat="$1" limit="${2:-15}"
    for _ in $(seq 1 $((limit * 4))); do
        zt capture-pane -p -t "$W" | grep -qF -- "$pat" && return 0
        sleep 0.25
    done
    return 1
}
drop_hx() { local w; w="$(t_win hx)"; [ -n "$w" ] && zt kill-window -t "$w"; sleep 0.4; }

# ── o: пикер файлов ────────────────────────────────────
popup_list files || t_fail "попап files не отрисовался"
screen="$(zt capture-pane -p -t "$W")"
assert_has "в пикере виден файл проекта" "$screen" "src.ts"
assert_has "видна строка тумблеров"      "$screen" "alt-h"
zt send-keys -t "$W" "src"
sleep 1.5
zt send-keys -t "$W" Enter
assert_has "o открыл выбранный файл" "$(hx_status)" "src.ts"
drop_hx

# ── /: живой поиск по тексту ───────────────────────────
popup_live grep || t_fail "попап grep не отрисовался"
zt send-keys -t "$W" "needle_here"
sleep 2
screen="$(zt capture-pane -p -t "$W")"
assert_has "поиск нашёл совпадение"        "$screen" "needle_here"
assert_has "в выдаче есть файл и строка"   "$screen" "doc.md:2"
zt send-keys -t "$W" Enter
sl="$(hx_status)"
assert_has "/ открыл найденный файл" "$sl" "doc.md"
# Регрессия: когда hx ещё не запущен, номер строки терялся — open поднимал
# новое окно как `hx файл`, без суффикса `:строка`.
assert_has "/ встал на найденную строку (hx поднимался с нуля)" "$sl" "2:1"
drop_hx

# ── повторный поиск в УЖЕ работающий hx ────────────────
popup_live grep || t_fail "попап grep не отрисовался (второй раз)"
zt send-keys -t "$W" "needle_here"
sleep 2
zt send-keys -t "$W" Enter
assert_has "/ встал на строку и в работающем hx" "$(hx_status)" "2:1"

# ── B: blame текущего файла ────────────────────────────
# Файл и строку blame берёт у hx сам; сейчас открыт doc.md на строке 2.
$Z open "$FIX/src.ts" 2
sleep 1.5
popup_list blame || t_fail "попап blame не отрисовался"
screen="$(zt capture-pane -p -t "$W")"
assert_has "blame показал автора правки" "$screen" "Bob"
assert_has "blame показал код строки"    "$screen" "amount"
zt send-keys -t "$W" Escape
sleep 0.8

# ── B встаёт на ТЕКУЩУЮ строку, а не на первую ─────────
# Регрессия: позиционирование висело на событии start, а на нём список ещё не
# прочитан, и fzf молча оставлял курсор на первой строке файла.
# Строка 4 добавлена Bob'ом, строка 1 — Alice: по автору в превью видно, куда
# встал попап.
# Проверяем по СООБЩЕНИЮ коммита в превью: в самом списке его нет (там sha,
# автор, дата и код), поэтому оно однозначно говорит, какая строка выбрана.
$Z open "$FIX/src.ts" 4
sleep 1.5
popup_list blame || t_fail "попап blame не отрисовался (строка 4)"
wait_text "ДОБАВИЛ" || wait_text "ПЕРВЫЙ"   # дождаться превью коммита
screen="$(zt capture-pane -p -t "$W")"
assert_has     "blame встал на строку курсора"    "$screen" "ПОЗЖЕ-ДОБАВИЛ"
assert_not_has "а не на первую строку файла"      "$screen" "САМЫЙ-ПЕРВЫЙ"
zt send-keys -t "$W" Escape
sleep 0.8

# ── D: дифф ханка под курсором ─────────────────────────
printf 'export function pay(amount) {\n  return amount * 99;\n}\n' > "$FIX/src.ts"
$Z open "$FIX/src.ts" 2
sleep 1.5
zt send-keys -t "$W" "cd '$FIX' && DELTA_PAGER='cat' $Z diff" Enter
sleep 3
screen="$(zt capture-pane -p -t "$W")"
assert_has "дифф показал новое значение" "$screen" "99"
zt send-keys -t "$W" q
sleep 0.5

# ── ?: шпаргалка ───────────────────────────────────────
t_load_conf
popup_list keys || t_fail "попап keys не отрисовался"
zt send-keys -t "$W" "проект"
sleep 1.5
screen="$(zt capture-pane -p -t "$W")"
assert_has "шпаргалка фильтруется по тексту" "$screen" "проект"
zt send-keys -t "$W" Escape
sleep 0.5

exit $FAILED
