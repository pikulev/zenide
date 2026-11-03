#!/usr/bin/env bash
# Прогон всех тестов: ./tests/run.sh [имя…]
#
# Покрыто то, что ломается молча: инъекция в helix, протокол @hx_skip_reload,
# чтение контекста, статус для бара, инварианты справки и попапы fzf целиком
# (t-popups.sh: ввод в fzf → файл открылся на нужной строке).
#
# Всё крутится на сокете zenide-test. Живая сессия (сокет default) не трогается.
set -u

cd "$(dirname "$0")" || exit 1

if [ $# -gt 0 ]; then
    tests=()
    for n in "$@"; do tests+=("t-${n#t-}.sh"); done
else
    tests=(t-*.sh)
fi

pass=0 fail=0 failed_names=""
for t in "${tests[@]}"; do
    [ -f "$t" ] || { printf '!! нет такого теста: %s\n' "$t" >&2; exit 2; }
    # Таймаут на тест: зависший helix или tmux не должен вешать прогон.
    if perl -e 'alarm shift; exec @ARGV' 120 bash "$t"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        failed_names="$failed_names $t"
    fi
    echo
done

printf '─────\nпрошло: %d, упало: %d%s\n' "$pass" "$fail" \
    "$([ -n "$failed_names" ] && printf ' →%s' "$failed_names")"
[ "$fail" -eq 0 ]
