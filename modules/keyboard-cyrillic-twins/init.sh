#!/usr/bin/env bash
# Автогенерация кириллических ДВОЙНИКОВ для всех prefix-биндов с латинской
# клавишей (кастомные + дефолтные tmux + будущие) — чтобы C-Space {буква}
# работал в русской раскладке. Префикс C-Space от раскладки не зависит, а
# следующая клавиша приходит кириллицей и не матчит bind; abc.sh не спасает
# (жмёшь до перехода). Двойник вешается на ТУ ЖЕ команду, что латинский оригинал.
#
# Запуск: из tmux.conf через `run-shell` в конце (когда все бинды уже определены).
# Идемпотентно: на reload перечитывает и переставляет; кириллические ключи в
# карту не входят → двойников-двойников не плодит.
#
# Карта латиница→кириллица — cyr-map.txt рядом (снята через UCKeyTranslate,
# com.apple.keylayout.Russian; см. rumap в истории). `/` `-` в RU те же → не в карте.
set -eu
dir="$(cd "$(dirname "$0")" && pwd)"
map="$dir/cyr-map.txt"
[ -r "$map" ] || exit 0

out="$(mktemp)"
tmux list-keys -T prefix | awk -v MAP="$map" '
  BEGIN { while ((getline l < MAP) > 0) { split(l, a, "\t"); m[a[1]] = a[2] } }
  match($0, /^bind-key[ \t]+-T prefix /) {
    rest = substr($0, RLENGTH + 1)          # "KEY   COMMAND..."
    split(rest, p, /[ \t]+/); key = p[1]    # первый токен = клавиша
    if (!(key in m)) next
    cmd = substr(rest, length(key) + 1)     # остаток = команда (кавычки/пробелы как есть)
    sub(/^[ \t]+/, "", cmd)
    printf "bind-key -T prefix %s %s\n", m[key], cmd
  }
' > "$out"
tmux source-file "$out"
rm -f "$out"
