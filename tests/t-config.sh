#!/usr/bin/env bash
# Инварианты конфига tmux. Здесь главное — не «работает ли», а «не выпало ли
# молча»: справка C-Space ? собирается из заметок -N, и бинд без заметки
# исчезает из неё БЕЗ единой ошибки. Такое ловится только проверкой.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT

echo "t-config: инварианты tmux.conf и справки"
t_setup

CONF="$REPO_ROOT/ide/tmux/tmux.conf"
KEYS="$REPO_ROOT/libexec/zenide/keys"
printf 'modules="keyboard-cyrillic-twins"\n' > "$ZENIDE_PROFILE/modules.local"

# ── 1. конфиг сорсится без ошибок ──────────────────────
err="$(zt source-file "$CONF" 2>&1)"
assert_eq "tmux.conf сорсится без ошибок" "$err" ""

# ── 2. у каждого своего бинда есть заметка -N ──────────
# Без -N клавиша не попадает в list-keys -N, а значит и в справку.
nonote="$(grep -nE '^bind(-key)?[[:space:]]' "$CONF" | grep -v -- '-N ' || true)"
assert_eq "все бинды с -N" "$nonote" ""

# ── 3. группы заметок совпадают с ORDER в справке ──────
order="$(sed -n "s/^ORDER='\(.*\)'.*/\1/p" "$KEYS" | head -1)"
[ -n "$order" ] || t_fail "не нашёл ORDER в $KEYS"
groups="$(sed -nE 's/^bind(-key)?[[:space:]]+-N[[:space:]]+"([^:]+):.*/\2/p' "$CONF" | sort -u)"
unknown=""
for g in $groups; do
    case " $order " in *" $g "*) ;; *) unknown="$unknown $g" ;; esac
done
assert_eq "все группы биндов есть в ORDER" "$unknown" ""

# ── 4. ожидаемые клавиши на месте ──────────────────────
keys_live="$(zt list-keys -N -P '' -T prefix 2>/dev/null | sed 's/^[[:space:]]*//')"
for k in f s o g G e E D B R Enter Tab Space '?' r; do
    case "$keys_live" in
    "$k "*|*"
$k "*) t_ok "бинд $k на месте" ;;
    *) t_fail "бинд $k потерялся" ;;
    esac
done

# ── 5. кириллические двойники навешены ─────────────────
# Двойник берётся по ФИЗИЧЕСКОЙ клавише: латинская f сидит там, где в RU «а»
# (а «ф» — на клавише a, и бинда a нет, поэтому двойника «ф» не существует).
# cyr-twins — отложенный run-shell, ему нужно дать добежать.
CYRMAP="$REPO_ROOT/modules/keyboard-cyrillic-twins/cyr-map.txt"
twin_of() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$CYRMAP"; }
for _ in $(seq 1 30); do
    zt list-keys -T prefix 2>/dev/null | awk '{print $4}' | grep -qvE '^[ -~]+$' && break
    sleep 0.1
done
live_keys="$(zt list-keys -T prefix 2>/dev/null | awk '{print $4}')"
for k in f g o B; do
    tw="$(twin_of "$k")"
    assert_has "двойник $k → $tw" "$live_keys" "$tw"
done
# ПОЛНОТА: после одной загрузки конфига двойник есть у КАЖДОЙ латинской
# клавиши из карты. Ручной прогон генератора для этого не нужен — проверяем
# именно то состояние, которое получает человек после `prefix r`.
cyr_live() { zt list-keys -T prefix 2>/dev/null | awk '{print $4}' | grep -vE '^[ -~]+$'; }
# Списки кладём в файлы, а не гоняем через пайп в цикле: `grep -q` закрывает
# пайп на первом совпадении, и пишущая сторона получает «Broken pipe».
cyr_live > "$FIX/cyr.txt"
printf '%s\n' "$live_keys" > "$FIX/lat.txt"
missing=""
while IFS="$(printf '\t')" read -r lat cyr; do
    [ -n "$lat" ] || continue
    # клавиша из карты вообще забиндена?
    grep -qxF -- "$lat" "$FIX/lat.txt" || continue
    grep -qxF -- "$cyr" "$FIX/cyr.txt" || missing="$missing ${lat}=>${cyr}"
done < "$CYRMAP"
assert_eq "двойник есть у каждого бинда из карты" "$missing" ""

# Идемпотентность: повторный прогон не плодит двойников-двойников
# (кириллических клавиш в карте нет, удваивать нечего). На этом держится
# безопасность `prefix r` — перечитывать конфиг можно сколько угодно раз.
n1="$(cyr_live | wc -l | tr -d ' ')"
z twins >/dev/null 2>&1
sleep 0.3
assert_eq "повторный прогон ничего не меняет" "$(cyr_live | wc -l | tr -d ' ')" "$n1"

# ── 6. хуки зарегистрированы ───────────────────────────
hooks="$(zt show-hooks -g 2>/dev/null)"
assert_has "хук session-window-changed" "$hooks" "session-window-changed"
assert_has "хук client-session-changed" "$hooks" "client-session-changed"

# ── 7. грабли формата: трейлинг «;#» и «\» в конце строки ──
bad="$(grep -nE ';[[:space:]]*#' "$CONF" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
assert_eq "нет трейлинг-комментария после «;»" "$bad" ""

# ── 8. бар: git-статус и интервал ──────────────────────
assert_has "status-right зовёт git-статус" "$(zt show -gv status-right)" "#("
assert_eq  "status-interval = 5"           "$(zt show -gv status-interval)" "5"

exit $FAILED
