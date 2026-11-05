#!/usr/bin/env bash
# Маршруты: системный DNS, IPv6, изоляция ошибок и конфиг как данные, без сети.
set -u
. "$(dirname "$0")/lib.sh"
FIX=$(mktemp -d "${TMPDIR:-/tmp}/zenide-routes.XXXXXX")
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/bin" "$FIX/profile" "$FIX/xdg/zenide-profile"
export ROUTES_CALLS="$FIX/calls"

cat > "$FIX/bin/dscacheutil" <<'EOF'
#!/bin/bash
printf 'dns %s\n' "$*" >> "$ROUTES_CALLS"
[ "$1 $2 $3" = '-q host -a' ] && [ "$4" = name ] || exit 2
case "$5" in
    dual.test)
        printf 'name: dual.test\nip_address: 192.0.2.1\nip_address: 192.0.2.1\nipv6_address: 2001:db8::1\n' ;;
    missing.test) exit 0 ;;
    fail.test) exit 1 ;;
    slow.test) exec sleep 30 ;;
    *) exit 2 ;;
esac
EOF
cat > "$FIX/bin/route" <<'EOF'
#!/bin/bash
printf 'route %s\n' "$*" >> "$ROUTES_CALLS"
[ "$1 $2" = '-n get' ] && [ "$#" -eq 4 ] || exit 2
case "$4" in
    192.0.2.1)
        [ "$3" = -inet ] || exit 2
        printf 'gateway: 192.0.2.254\ninterface: en0\nflags: <UP,GATEWAY>\n' ;;
    2001:db8::1)
        [ "$3" = -inet6 ] || exit 2
        printf 'gateway: fe80::1%%utun7\ninterface: utun7\nflags: <UP,GATEWAY>\n' ;;
    192.0.2.2) printf 'route: writing to routing socket: not in table\n' >&2; exit 0 ;;
    192.0.2.3) printf 'interface: lo0\nflags: <UP,HOST,REJECT>\n' ;;
    192.0.2.4) printf 'route: socket: Operation not permitted\n' >&2; exit 1 ;;
    127.0.0.1) printf 'interface: lo0\nflags: <UP,HOST,LOCAL>\n' ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$FIX/bin/dscacheutil" "$FIX/bin/route"
export PATH="$FIX/bin:$PATH"

printf '# Комментарий\r\n\r\n dual.test # оба семейства\r\n127.0.0.1' > "$FIX/hosts"
out=$("$REPO_ROOT/shell/bin/myroutes" --config "$FIX/hosts")
assert_eq 'список с комментариями, CRLF и без последнего LF принят' "$?" 0
assert_has 'есть IPv4' "$out" 192.0.2.1
assert_has 'есть IPv6' "$out" 2001:db8::1
assert_has 'виден туннель' "$out" туннель
assert_has 'виден шлюз' "$out" 'fe80::1%utun7'
assert_has 'loopback локальный' "$out" локальный
assert_eq 'одинаковые ответы DNS не дублируют маршрут' "$(grep -c 'route -n get -inet 192.0.2.1$' "$ROUTES_CALLS")" 1
assert_eq 'IP-литерал не запускает DNS' "$(grep -c '^dns ' "$ROUTES_CALLS")" 1

out=$("$REPO_ROOT/shell/bin/myroutes" missing.test fail.test 192.0.2.2 192.0.2.3 192.0.2.4 127.0.0.1 2> "$FIX/errors")
assert_eq 'частичный сбой возвращает 1' "$?" 1
assert_has 'пустой DNS объяснён' "$out" 'DNS: адресов нет'
assert_has 'сбой DNS объяснён' "$out" 'ошибка/таймаут DNS'
assert_has 'нулевой код route не скрывает отсутствие маршрута' "$out" 'нет маршрута'
assert_has 'ошибка чтения маршрута' "$out" 'маршрут недоступен'
assert_has 'причина route сохранена' "$(cat "$FIX/errors")" 'not in table'
assert_has 'REJECT не показан как рабочий маршрут' "$out" блокировка
assert_has 'после ошибок проверен следующий хост' "$out" 127.0.0.1

out=$("$REPO_ROOT/shell/bin/myroutes" slow.test 127.0.0.1 2>/dev/null)
assert_eq 'зависший DNS ограничен таймаутом' "$?" 1
assert_has 'после таймаута проверен следующий хост' "$out" 127.0.0.1

printf '192.0.2.1\n' > "$FIX/profile/myroutes.conf"
printf '127.0.0.1\n' > "$FIX/profile/myroutes.local"
out=$(ZENIDE_PROFILE="$FIX/profile" "$REPO_ROOT/shell/bin/myroutes")
assert_eq 'личный профиль прочитан' "$?" 0
assert_has 'local заменил conf' "$out" 127.0.0.1
assert_not_has 'conf не примешан к local' "$out" 192.0.2.1
printf '127.0.0.1\n' > "$FIX/xdg/zenide-profile/myroutes.conf"
out=$(ZENIDE_PROFILE='' XDG_CONFIG_HOME="$FIX/xdg" "$REPO_ROOT/shell/bin/myroutes")
assert_eq 'якорь профиля прочитан' "$?" 0
assert_has 'якорь содержит нужный хост' "$out" 127.0.0.1
out=$("$REPO_ROOT/shell/bin/myroutes" --config "$FIX/нет-файла" 127.0.0.1)
assert_eq 'аргументы заменяют конфиг' "$?" 0

: > "$ROUTES_CALLS"
for invalid in 'https://example.com' 'example.com:443' '-bad' '$(touch EXECUTED)' 'host second'; do
    printf '%s\n' "$invalid" > "$FIX/bad"
    "$REPO_ROOT/shell/bin/myroutes" --config "$FIX/bad" > /dev/null 2>&1
    assert_eq "некорректная строка отвергнута: $invalid" "$?" 2
done
assert_eq 'некорректный конфиг не запускал сетевые команды' "$(cat "$ROUTES_CALLS")" ''
: > "$FIX/empty"
"$REPO_ROOT/shell/bin/myroutes" --config "$FIX/empty" >/dev/null 2>&1
assert_eq 'пустой список диагностирован' "$?" 2

exit "$FAILED"
