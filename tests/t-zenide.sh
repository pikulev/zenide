#!/usr/bin/env bash
# Диспетчер, слоты и модули: то, что появилось вместе с `zenide`.
# Проверяем в том числе ЗАМЕНЯЕМОСТЬ слота — обещание модульности должно быть
# проверяемым, а не только написанным в README.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT

echo "t-zenide: диспетчер, слоты, модули"

Z="$REPO_ROOT/bin/zenide"

t_setup
# окна должны оставаться после выхода команды — иначе не проверить их имена
zt set -g remain-on-exit on

# ── диспетчер ──────────────────────────────────────────
out="$("$Z" help 2>&1)"
assert_has "help перечисляет подкоманды" "$out" "blame"
assert_has "help включает слот редактора" "$out" "open"
"$Z" нет-такой-команды >/dev/null 2>&1
assert_eq "неизвестная подкоманда → код 2" "$?" "2"
assert_has "version печатает корень" "$("$Z" version)" "$(cd "$(dirname "$0")/.." && pwd -P)"

# ── модули ─────────────────────────────────────────────
out="$("$Z" modules list)"
assert_has "модуль force-latin виден"      "$out" "keyboard-force-latin"
assert_has "модуль cyrillic-twins виден"   "$out" "keyboard-cyrillic-twins"

# ── doctor ─────────────────────────────────────────────
out="$("$Z" doctor 2>&1)" && rc=0 || rc=$?
assert_eq  "doctor доволен этой машиной" "$rc" "0"
assert_has "doctor проверяет соседей"    "$out" "focus-lost"
assert_has "doctor показывает слоты"     "$out" "git-TUI"

# ── profile: данные вместо хардкода ────────────────────
# Ядро не должно знать ничьих путей: подставляем свой профиль и ждём РОВНО
# то, что в нём написано.
prof="$FIX/profile"
mkdir -p "$prof" "$FIX/p1" "$FIX/p2"
cat > "$prof/projects.conf" <<EOF
roots=("$FIX")
standalone=()
containers=()
EOF
list="$(ZENIDE_PROFILE="$prof" "$Z" project --list)"
assert_has "project видит проект из профиля"      "$list" "$FIX/p1"
assert_not_has "project не лезет в чужие корни"   "$list" "$HOME/code"

# ── слот git_tui: заменяемость ─────────────────────────
# Имя окна = имя инструмента, поэтому подмена слота видна сразу.
cat > "$prof/modules.conf" <<'EOF'
editor=helix
git_tui=gitui
files=yazi
search=scooter
modules=""
EOF
ZENIDE_PROFILE="$prof" "$Z" window git
sleep 0.5
assert_has "git_tui=gitui → окно gitui" "$(zt list-windows -t t -F '#{window_name}')" "gitui"

cat > "$prof/modules.conf" <<'EOF'
editor=helix
git_tui=tig
files=yazi
search=scooter
modules=""
EOF
ZENIDE_PROFILE="$prof" "$Z" window git
sleep 0.5
assert_has "git_tui=tig → окно tig" "$(zt list-windows -t t -F '#{window_name}')" "tig"

# ── window: имя search — РОЛЬ, а не инструмент ─────────
ZENIDE_PROFILE="$prof" "$Z" window search
sleep 0.5
wins="$(zt list-windows -t t -F '#{window_name}')"
assert_has     "окно замены названо search"  "$wins" "search"
assert_not_has "а не именем инструмента"     "$wins" "scooter"

# ── window идемпотентен: второй вызов переключает ──────
before="$(zt list-windows -t t -F '#{window_name}' | grep -c '^search$' | tr -d ' ')"
ZENIDE_PROFILE="$prof" "$Z" window search
sleep 0.3
after="$(zt list-windows -t t -F '#{window_name}' | grep -c '^search$' | tr -d ' ')"
assert_eq "повторный вызов не плодит окон" "$after" "$before"

# ── справка собирается ─────────────────────────────────
t_load_conf
out="$("$Z" keys --print 2>/dev/null | sed -e 's/\x1b\[[0-9;]*m//g')"
assert_has "в справке есть секции"           "$out" "── проекты ──"
assert_has "в справке есть клавиши попапов"  "$out" "── внутри попапов и окон ──"
assert_has "метка попапа выведена из бинда"  "$out" "Enter проект → сессия"
assert_has "дефолты tmux отдельной секцией"  "$out" "── дефолты tmux ──"

exit $FAILED
