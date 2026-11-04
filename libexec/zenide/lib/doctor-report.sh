# Общие записи для текстового doctor и JSON. Проверки не знают об интерфейсе.
# Никаких Python/jq: аварийная диагностика должна работать без TUI-окружения.
# shellcheck shell=bash

format="${1:-text}"

record_count=0
group=""
group_title=""

json_string() {
    local value="$1" char i
    local LC_ALL=C
    printf '"'
    for ((i = 0; i < ${#value}; i++)); do
        char="${value:i:1}"
        case "$char" in
        '"' | '\') printf '\\%s' "$char" ;;
        [[:cntrl:]]) printf '\\u%04x' "'$char" ;;
        *) printf '%s' "$char" ;;
        esac
    done
    printf '"'
}

section() {
    group="$1" group_title="$2"
    [ "$format" = json ] || printf '\n%s\n' "$group_title"
}

# emit <id> <ok|warn|error|info> <название> <наблюдение> [инструкция] [файл]
# id стабилен при изменении статуса; инструкция — текст, а не shell-действие.
emit() {
    local id="$1" status="$2" title="$3" detail="$4" hint="${5:-}" file="${6:-}"
    local key value mark
    [ "$status" != error ] || fail=1
    if [ "$format" = json ]; then
        [ "$record_count" -eq 0 ] || printf ','
        printf '\n{'
        for key in id group group_title status title detail hint file; do
            case "$key" in
            id) value="$id" ;; group) value="$group" ;; group_title) value="$group_title" ;;
            status) value="$status" ;; title) value="$title" ;; detail) value="$detail" ;;
            hint) value="$hint" ;; file) value="$file" ;;
            esac
            [ "$key" = id ] || printf ','
            printf '"%s":' "$key"
            json_string "$value"
        done
        printf '}'
    else
        case "$status" in
        ok) mark=ok ;; warn) mark='~' ;; error) mark=нет ;; info) mark='·' ;;
        esac
        printf '  %-5s %s: %s\n' "$mark" "$title" "$detail"
        [ -z "$hint" ] || printf '        %s\n' "$hint"
    fi
    record_count=$((record_count + 1))
}

report_begin() {
    if [ "$format" = json ]; then
        printf '{"schema_version":1,"root":'
        json_string "$ZENIDE_ROOT"
        printf ',"profile":'
        json_string "$ZENIDE_PROFILE"
        printf ',"checks":['
    fi
}

report_end() {
    if [ "$format" = json ]; then
        printf '\n],"exit_code":%d}\n' "$fail"
    elif [ "$fail" -eq 0 ]; then
        printf '\nОбязательное на месте.\n'
    else
        printf '\nЕсть НЕработающее — см. «нет» выше.\n'
    fi
}
