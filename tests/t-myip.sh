#!/usr/bin/env bash
# myip: простой запрос ifconfig.me; регрессии фона статусбара без сети.
set -u
. "$(dirname "$0")/lib.sh"
trap t_teardown EXIT
t_setup

mkdir -p "$FIX/bin"
cat > "$FIX/bin/curl" <<'EOF'
#!/bin/sh
for url do :; done
[ "$url" = https://ifconfig.me/ip ] || exit 2
printf '192.0.2.1'
EOF
chmod +x "$FIX/bin/curl"
assert_eq "myip возвращает внешний IP" "$(PATH="$FIX/bin:$PATH" "$REPO_ROOT/shell/bin/myip")" '192.0.2.1'

zt set -g status-bg colour236
t_load_conf
assert_not_has "в статусе нет myip" "$(zt show -gv status-right)" myip
zt new-session -d -s view -x 200 -y 50 "env -u TMUX tmux -L $SOCK attach-session -t t"
zt set -t view status off
for _ in $(seq 1 40); do
    zt capture-pane -p -t view: | grep -qE '[0-9]{2}:[0-9]{2}' && break
    sleep 0.25
done
assert_not_has "старый серый фон не перекрыл тему" "$(zt capture-pane -ep -t view:)" '[48;5;236m'
assert_has "после проекта сброшен фон" "$(zt capture-pane -ep -t view:)" $'[48;2;82;80;83m t \033[0m'

exit "$FAILED"
