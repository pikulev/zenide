#!/usr/bin/env bash
# Ошибка тестового сервера должна остановить тест ДО обращения к мосту.
set -u
. "$(dirname "$0")/lib.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/zenide-harness.XXXXXX")"
WORK="$(cd "$WORK" && pwd)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/tmux"
chmod +x "$WORK/bin/tmux"
echo 't-harness: отказ запуска tmux'
out="$(PATH="$WORK/bin:$PATH" bash -c '
    . "$1/tests/lib.sh"
    trap t_teardown EXIT
    t_setup
    echo CONTINUED_AFTER_FAILURE
' _ "$REPO_ROOT" 2>&1)"
assert_eq 'отказ сервера завершает тест с ошибкой' "$?" 1
assert_not_has 'мост не запускается после отказа сервера' "$out" CONTINUED_AFTER_FAILURE

# Лаунчер try также изолирует HOME: XDG одного недостаточно для истории шелла.
mkdir -p "$WORK/clone/ide" "$WORK/clone/profile"
cp "$REPO_ROOT/try" "$WORK/clone/"
cp "$REPO_ROOT"/profile/*.conf "$WORK/clone/profile/"
cat > "$WORK/bin/tmux" <<'SH'
#!/bin/sh
case "$*" in *new-session*) printf '%s\n%s\n' "$HOME" "$XDG_CONFIG_HOME" > "$ZENIDE_TEST_REPORT" ;; esac
SH
chmod +x "$WORK/bin/tmux"
PATH="$WORK/bin:$PATH" ZENIDE_TEST_REPORT="$WORK/try-env" "$WORK/clone/try" --keep <<< '' >/dev/null
assert_eq 'try подменяет HOME' "$(sed -n 1p "$WORK/try-env")" "$WORK/clone/.sandbox/home"
assert_eq 'try подменяет XDG' "$(sed -n 2p "$WORK/try-env")" "$WORK/clone/.sandbox/config"
exit "$FAILED"
