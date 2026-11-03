#!/usr/bin/env bash
# Чтение состояния из helix: какой файл и строка в СФОКУСИРОВАННОМ буфере.
# На этом держатся все контекстные прыжки (D, B, E, G) — без ctx они уезжают
# на случайный файл. Проверяем и при сплитах: парсинг статусбара там врёт,
# инъекция %{buffer_name} — нет.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT

echo "t-ctx: контекст сфокусированного буфера hx"
t_setup
t_load_conf
t_hx_start a.txt || exit 1

z open "$FIX/b.txt" 5
sleep 1

out="$(z ctx)"
assert_has "ctx отдал файл"   "$(printf '%s' "$out" | sed -n 1p)" "b.txt"
assert_eq  "ctx отдал строку" "$(printf '%s' "$out" | sed -n 2p)" "5"

# ── сплит: фокус должен определяться по hx, а не по последнему статуслайну ──
pane="$(zt list-panes -t "$(t_win hx)" -F '#{pane_id}' | head -1)"
zt send-keys -t "$pane" Escape
sleep 0.2
printf 'vsplit a.txt' | zt load-buffer -b tctx -
zt send-keys -t "$pane" ":"
zt paste-buffer -d -p -b tctx -t "$pane"
zt send-keys -t "$pane" Enter
sleep 1.2

out="$(z ctx)"
assert_has "при сплите ctx видит сфокусированный буфер" \
           "$(printf '%s' "$out" | sed -n 1p)" "a.txt"

# Имена проходят через оба парсера как данные, без shell/Helix-экспансий.
for name in 'two words.txt' "it's.txt" '$(touch CTX_EXECUTED).txt' '`touch CTX_BACKTICK`.txt' '%sh{touch HX_EXECUTED}.txt' 'a"b\c.txt'; do
    printf 'SPECIAL_CONTENT\nsecond\n' > "$FIX/$name"
    z open "$FIX/$name" 2
    sleep 0.2
    out="$(z ctx)"
    assert_eq "ctx сохранил имя: $name" "$(printf '%s' "$out" | sed -n 1p)" "$name"
    assert_eq "ctx сохранил строку" "$(printf '%s' "$out" | sed -n 2p)" 2
done
for marker in CTX_EXECUTED CTX_BACKTICK HX_EXECUTED; do
    [ ! -e "$FIX/$marker" ] && t_ok "не исполнил $marker" || t_fail "исполнил имя файла: $marker"
done

mkdir -p "$FIX/tmp ' % space"
out="$(TMPDIR="$FIX/tmp ' % space" z ctx)"
assert_has "ctx работает с кавычками и % в TMPDIR" "$out" 'a"b\c.txt'

# Конкурирующие отправители не перемешивают командные строки одного пейна.
z open "$FIX/b.txt" 4 &
sender=$!
z ctx > "$FIX/parallel-context" &
reader=$!
wait "$sender" || t_fail 'параллельный open завершился с ошибкой'
wait "$reader" || t_fail 'параллельный ctx завершился с ошибкой'
out="$(z ctx)"
assert_eq "параллельная доставка сохранила файл" "$(printf '%s' "$out" | sed -n 1p)" b.txt
assert_eq "параллельная доставка сохранила строку" "$(printf '%s' "$out" | sed -n 2p)" 4

exit $FAILED
