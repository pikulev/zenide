#!/usr/bin/env bash
# Слоты, окружение и идентичность проекта; реальные процессы на тестовом tmux.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT

echo 't-navigation: переходы сохраняют проект, окружение и процесс'
t_setup

# Подставной git-TUI фиксирует окружение, которое действительно получил.
mkdir -p "$FIX/bin"
cat > "$FIX/bin/lazygit" <<'SH'
#!/bin/sh
printf '%s\n' "$XDG_CONFIG_HOME" > "$ZENIDE_TEST_REPORT"
exec sleep 60
SH
cp "$FIX/bin/lazygit" "$FIX/bin/fakefiles"
chmod +x "$FIX/bin/lazygit" "$FIX/bin/fakefiles"
# Для new-window tmux берёт PATH также из окружения вызывающего клиента.
export PATH="$FIX/bin:$PATH"
zt set-environment -t t PATH "$PATH"
zt set-environment -g ZENIDE_TEST_REPORT "$FIX/environment"
z window git
for _ in $(seq 1 30); do [ -s "$FIX/environment" ] && break; sleep 0.1; done
assert_eq 'git-TUI сохранил XDG песочницы' "$(cat "$FIX/environment")" "$XDG_CONFIG_HOME"

printf 'files=fakefiles\n' > "$ZENIDE_PROFILE/modules.local"
z jump files
assert_has 'контекстный переход уважает слот files' "$(t_win fakefiles)" '@'
assert_eq 'альтернативный слот не запустил yazi' "$(t_win yazi)" ''
printf 'files=yazi\n' > "$ZENIDE_PROFILE/modules.local"

# E должен перейти к файлу и оставить тот же процесс yazi.
t_hx_start deep/nested/c.txt || exit 1
z window files
ywin="$(t_win yazi)"
for _ in $(seq 1 50); do
    t_pane yazi | grep -q 'deep' && break
    sleep 0.1
done
ypid="$(zt display-message -p -t "$ywin" '#{pane_pid}')"
z jump files
for _ in $(seq 1 50); do
    t_pane yazi | grep -q 'c.txt' && break
    sleep 0.1
done
assert_eq 'переход сохранил окно yazi' "$(t_win yazi)" "$ywin"
assert_eq 'переход сохранил процесс yazi' "$(zt display-message -p -t "$ywin" '#{pane_pid}')" "$ypid"
assert_has 'yazi перешёл к файлу редактора' "$(t_pane yazi)" c.txt

# У headless-сервера нет клиента для switch-client; проверяем созданные сессии.
mkdir -p "$FIX/one/api" "$FIX/two/api" "$FIX/foo.bar" "$FIX/foo_bar"
for path in "$FIX/one/api" "$FIX/two/api" "$FIX/foo.bar" "$FIX/foo_bar"; do
    z project "$path" >/dev/null 2>&1 || true
done
assert_eq 'четыре проекта не склеились' "$(zt list-sessions -F '#{session_id}' | wc -l | tr -d ' ')" 5
z project "$FIX/two/api" >/dev/null 2>&1 || true
assert_eq 'повторный выбор переиспользует сессию' "$(zt list-sessions -F '#{session_id}' | wc -l | tr -d ' ')" 5

exit "$FAILED"
