#!/usr/bin/env bash
# git-статус для status-right. Крутится у каждого клиента раз в несколько
# секунд, поэтому важны две вещи: не трогать index.lock (GIT_OPTIONAL_LOCKS=0)
# и молчать там, где не репозиторий.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT

echo "t-status: git-статус проекта для бара"
t_setup

branch="$(git -C "$FIX" rev-parse --abbrev-ref HEAD)"

out="$(z status "$FIX")"
assert_has "показал ветку"        "$out" "$branch"
assert_has "чистое дерево → ☘️"   "$out" "☘️"

printf 'untracked\n' > "$FIX/new.txt"
out="$(z status "$FIX")"
assert_has "untracked посчитан"   "$out" "…1"
assert_not_has "чистого ☘️ больше нет" "$out" "☘️"

git -C "$FIX" add new.txt
out="$(z status "$FIX")"
assert_has "staged посчитан"      "$out" "📦1"

printf 'dirty\n' >> "$FIX/a.txt"
out="$(z status "$FIX")"
assert_has "unstaged посчитан"    "$out" "🎈1"

# не репозиторий → пусто, без шума в баре
assert_eq "вне репозитория пусто" "$(z status "${TMPDIR:-/tmp}")" ""
# несуществующий каталог → тоже пусто
assert_eq "несуществующий путь пуст" "$(z status "$FIX/nope")" ""

# «#» в имени ветки не должен стать разметкой tmux
git -C "$FIX" checkout -q -b 'feat/i#42'
out="$(z status "$FIX")"
assert_has "«#» экранирован в ##" "$out" "i##42"

exit $FAILED
