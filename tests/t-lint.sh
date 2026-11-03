#!/usr/bin/env bash
# Прогон shellcheck по всем шелл-скриптам репозитория. Самая дешёвая страховка
# при переезде: опечатка в пути или потерянная кавычка видны сразу, без запуска.
#
# Осторожно: комментарий, НАЧИНАЮЩИЙСЯ словом shellcheck, линтер разбирает как
# свою директиву и падает с SC1072 — поэтому строку выше так и не напишешь.
set -u
. "$(dirname "$0")/lib.sh"

echo "t-lint: shellcheck"

if ! command -v shellcheck >/dev/null 2>&1; then
    printf '  skip линтер не установлен (brew install shellcheck, либо mise install — в mise.toml запинена версия)\n'
    exit 0
fi

# Версия в выводе не для красоты: правила между релизами меняются, и «вчера
# было зелено» без неё необъяснимо. В mise.toml репозитория версия запинена —
# но линт не требует mise: любой shellcheck с PATH годится, просто результат
# тогда зависит от его версии.
sc_ver="$(shellcheck --version 2>/dev/null | awk '/^version:/ {print $2}')"

cd "$REPO_ROOT" || exit 1

# Линтим только самостоятельные скрипты — опознаём по shebang. Фрагменты для
# zsh (`shell/parts/*`, тема omz) shebang'а не имеют и отсеиваются сами: у zsh
# свой синтаксис, линтер ему не судья. Явно исключаем чужой код и легаси.
is_ours() {
    case "$1" in
    ide/yazi/plugins/* | attic/*) return 1 ;;
    esac
    [ -f "$1" ] && head -1 "$1" | grep -qE '^#!.*(ba)?sh'
}

# Трекаемые ПЛЮС новые нетрекаемые (--others --exclude-standard): иначе свежий
# скрипт не линтуется до первого коммита — то есть ровно тогда, когда опечатка
# в нём наиболее вероятна.
files=""
while IFS= read -r f; do
    is_ours "$f" && files="$files $f"
done <<EOF
$(git ls-files; git ls-files --others --exclude-standard)
EOF

# -S warning: стилевые info не нужны, ловим только то, что ломает поведение.
# Отключено осознанно:
#   SC1091 — не ходим по `source` в чужие файлы;
#   SC2016 — одинарные кавычки в awk-программах и форматах tmux: `$` и `#{}`
#            там намеренно не раскрываются;
#   SC2088 — ложное срабатывание: `"~/"*)` — это case-ПАТТЕРН на литеральную
#            тильду, которую отдаёт helix в %{buffer_name}, а не путь;
#   SC2155 — `export X="$(mktemp …)"` в попапах: маскировка кода возврата
#            mktemp здесь безвредна, а разделение раздувает преамбулу.
# shellcheck disable=SC2086
if shellcheck -S warning -e SC1091,SC2016,SC2088,SC2155 -- $files; then
    # shellcheck disable=SC2086
    t_ok "shellcheck ${sc_ver:-?} чист ($(printf '%s\n' $files | grep -c . | tr -d ' ') файлов)"
else
    t_fail "shellcheck нашёл замечания"
fi

exit $FAILED
