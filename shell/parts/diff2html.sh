diffh() {
    # Получаем все переданные аргументы как заголовок и передаем их также для diff
    local params="$*"
    diff2html -i=command -s=side --su=open --title="git diff $params" -- "$@"
}

diffh-pipe() {
    diff2html -i=stdin -s=side --su=open --title="$@"
}