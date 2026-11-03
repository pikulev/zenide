#!/usr/bin/env bash
# Установка zenide. БЕЗ АРГУМЕНТОВ НИЧЕГО НЕ ДЕЛАЕТ — печатает план и выходит.
# Это умолчание, а не опция: человек ставит чужой сетап поверх своих конфигов,
# и первое, что ему нужно, — увидеть, что именно с ними случится.
#
# Пакеты не ставит (`brew bundle --file=Brewfile`) и личное окружение не
# настраивает (bootstrap.sh — он мой и зовёт этот скрипт).
#
# Использование:
#   ./install.sh                     показать план и выйти
#   ./install.sh --apply             применить
#   ./install.sh --with helix,yazi   добавить конфиги соседей
#   ./install.sh --with slot,taste   добавить целыми слоями (см. ide/LAYERS)
#   ./install.sh --with all          всё, КРОМЕ global
#   ./install.sh --copy --apply      копии вместо симлинков (git pull не
#                                    будет менять боевой конфиг)
#   ./install.sh --uninstall         откатить по манифесту
set -euo pipefail
cd "$(dirname "$0")" || exit 1
ROOT="$PWD"

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/zenide"
MANIFEST="$STATE/manifest"
ANCHOR="$CONFIG/zenide-profile"

APPLY=0 MODE=link WITH="" UNINSTALL=0
while [ $# -gt 0 ]; do
    case "$1" in
    --apply) APPLY=1 ;;
    --copy) MODE=copy ;;
    --uninstall) UNINSTALL=1 ;;
    --with)
        shift
        WITH="${1:-}"
        [ -n "$WITH" ] || {
            printf 'нужен список после --with\n' >&2
            exit 2
        }
        ;;
    --with=*) WITH="${1#--with=}" ;;
    -h | --help)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        printf 'неизвестный аргумент: %s (--help)\n' "$1" >&2
        exit 2
        ;;
    esac
    shift
done

c_dim=$'\033[38;5;242m' c_bold=$'\033[1m' c_warn=$'\033[33m' c_off=$'\033[0m'
say() { printf '  %s\n' "$1"; }
head_() { printf '\n%s%s%s\n' "$c_bold" "$1" "$c_off"; }

# Отпечаток установленной копии. Время доступа не учитывается: чтение
# конфигов не превращает их в изменённые. Ошибка чтения запрещает удаление.
fingerprint() {
    local path="$1"
    if [ -L "$path" ]; then
        return 1
    elif [ -d "$path" ]; then
        (
            cd "$path" || exit 1
            find . -type d -print0 || exit 1
            find . -type f -exec shasum -a 256 -- {} + || exit 1
            find . -type l -exec sh -c '
                for p do printf "%s\0%s\0" "$p" "$(readlink "$p")"; done
            ' sh {} + || exit 1
            find . ! -type d ! -type f ! -type l -print0 || exit 1
        ) | shasum -a 256 | awk '{print "sha256:" $1}'
    elif [ -f "$path" ]; then
        shasum -a 256 < "$path" | awk '{print "sha256:" $1}'
    else
        return 1
    fi
}

preserve() {
    local path="$1" saved
    saved="$(mktemp -d "$path.saved.XXXXXXXX")" || return
    mv "$path" "$saved/value" || return
    say "сохранено изменённое или неизвестное: $saved/value"
}

# ── откат ──────────────────────────────────────────────
if [ "$UNINSTALL" = 1 ]; then
    head_ "откат"
    [ -r "$MANIFEST" ] || { say "нет манифеста $MANIFEST"; exit 1; }
    # Разворачиваем ЖУРНАЛ, без дедупликации: install A → install B →
    # uninstall обязан вернуть состояние ДО A. После успешного шага снимаем
    # только его запись; при ошибке остаток журнала остаётся для повторения.
    while [ -s "$MANIFEST" ]; do
        IFS=$'\t' read -r kind path detail < <(tail -n 1 "$MANIFEST")
        case "$kind" in
        link | copy)
            if [ -L "$path" ] || [ -e "$path" ]; then
                owned=0
                if [ "$kind" = link ] && [ -L "$path" ] && [ "$(readlink "$path")" = "$detail" ]; then
                    owned=1
                elif [ "$kind" = copy ] && [[ "$detail" == sha256:* ]] &&
                    actual="$(fingerprint "$path")" && [ "$actual" = "$detail" ]; then
                    owned=1
                fi
                if [ "$owned" = 1 ]; then
                    rm -rf "$path"
                    say "снято: $path"
                else
                    # Старый манифест без отпечатков тоже безопасен: копии
                    # сохраняются целиком. Ссылки проверяются по их цели.
                    preserve "$path"
                fi
            fi
            ;;
        backup)
            [ -e "$detail" ] || [ -L "$detail" ] || {
                printf 'нет бэкапа %s — откат остановлен, манифест сохранён\n' "$detail" >&2
                exit 1
            }
            if [ -e "$path" ] || [ -L "$path" ]; then preserve "$path"; fi
            mv "$detail" "$path"
            say "возвращено из бэкапа: $path"
            case "$detail" in *.backup.*/value) rmdir "${detail%/value}" ;; esac
            ;;
        keep) say "личное оставлено: $path" ;;
        *) printf 'неизвестная запись манифеста: %s\n' "$kind" >&2; exit 1 ;;
        esac
        next="$(mktemp "$STATE/manifest.XXXXXXXX")"
        sed '$d' "$MANIFEST" > "$next"
        mv "$next" "$MANIFEST"
    done
    rm -f "$MANIFEST"
    rmdir "$STATE" 2>/dev/null || true
    printf '\nОткат завершён. Изменённые копии сохранены рядом в *.saved.*/value.\n'
    printf 'Пакеты, окружение и личный профиль не удаляются.\n'
    exit 0
fi

# ── слои из ide/LAYERS ─────────────────────────────────
# Единственный источник правды о том, что обязательно, что предлагается и что
# трогает мир за пределами IDE. Дублировать список тулов здесь нельзя: он
# протух бы в день добавления каталога в ide/.
layer_of() { # layer_of <тул> → слой
    awk -F'|' -v t="$1" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2)
          if ($1 == t) { print $2; exit } }' ide/LAYERS
}
breaks_of() { # breaks_of <тул> → что сломается без конфига
    awk -F'|' -v t="$1" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $4)
          if ($1 == t) { print $4; exit } }' ide/LAYERS
}
tools_in_layer() { # tools_in_layer <слой> → список тулов
    awk -F'|' -v l="$1" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2)
          if ($2 == l) print $1 }' ide/LAYERS
}

# Что ставим сверх ядра. `global` в `all` НЕ входит: git и prettier меняют
# поведение вне zenide, такое берут только поимённо.
selected=""
add_sel() { case " $selected " in *" $1 "*) ;; *) selected="$selected $1" ;; esac; }
for item in ${WITH//,/ }; do
    case "$item" in
    all) for t in $(tools_in_layer contract) $(tools_in_layer slot) $(tools_in_layer taste); do add_sel "$t"; done ;;
    contract | slot | taste | global) for t in $(tools_in_layer "$item"); do add_sel "$t"; done ;;
    *)
        if [ -d "ide/$item" ]; then
            add_sel "$item"
        else
            printf 'нет такого тула или слоя: %s\n' "$item" >&2
            exit 2
        fi
        ;;
    esac
done

# ── план ───────────────────────────────────────────────
# Сначала СОБИРАЕТСЯ целиком, потом печатается, и только потом исполняется.
# Иначе «покажи, что сделаешь» неотличимо от «делай и комментируй».
plan=() backups=()
add() { plan+=("$1"); }

plan_put() { # plan_put <источник> <назначение> <подпись>
    local src="$1" dst="$2" label="$3" tgt
    if [ -L "$dst" ]; then
        tgt="$(readlink "$dst")"
        if [ "$tgt" = "$src" ] && { [ "$MODE" = link ] || [ "$dst" = "$HOME/.local/bin/zenide" ]; }; then
            add "ok|$dst|$label: уже на месте"
            return
        fi
        # НАШ симлинк (цель внутри клона) — можно трогать свободно: его цель
        # восстановима из этого же репозитория.
        case "$tgt" in
        "$ROOT" | "$ROOT"/*)
            if [ "$tgt" = "$src" ] && [ "$MODE" = link ]; then
                add "ok|$dst|$label: уже на месте"
            else
                add "relink|$src|$dst|$label: симлинк перенаправлен"
            fi
            return
            ;;
        esac
        # ЧУЖОЙ симлинк — stow, chezmoi, yadm, ln руками. Сюда НЕЛЬЗЯ ставить
        # `ln -sfn`: цель чужой стрелки не записана больше нигде, и откат
        # вернуть её не сможет. Поэтому сдвигаем сам симлинк, как файл: `mv`
        # не разыменовывает, в бэкап уезжает стрелка целиком.
        add "backup|$src|$dst|$label"
        backups+=("$dst")
        return
    fi
    if [ -e "$dst" ]; then
        add "backup|$src|$dst|$label"
        backups+=("$dst")
        return
    fi
    add "new|$src|$dst|$label"
}

# ядро: без этого zenide нет
plan_put "$ROOT" "$CONFIG/zenide" "корень zenide"
for t in $(tools_in_layer core); do
    plan_put "$ROOT/ide/$t" "$CONFIG/$t" "$t (ядро)"
done
# Даже в --copy входная ссылка ведёт в УСТАНОВЛЕННОЕ ядро, не в клон.
plan_put "$CONFIG/zenide/bin/zenide" "$HOME/.local/bin/zenide" "zenide на PATH"

# якорь профиля: РЕАЛЬНЫЙ каталог здесь — внешний профиль пользователя, он
# главнее нашего симлинка и в бэкап не уезжает
if [ -e "$ANCHOR" ] && [ ! -L "$ANCHOR" ]; then
    add "ok|$ANCHOR|якорь профиля: внешний профиль на месте, не трогаю"
else
    plan_put "$ROOT/profile" "$ANCHOR" "якорь профиля"
fi

# выбранные соседи
for t in $selected; do
    [ "$(layer_of "$t")" = core ] && continue # уже поставлен как ядро
    if [ "$t" = prettier ]; then
        # prettier не умеет XDG: ищет .prettierrc от файла вверх по дереву
        plan_put "$ROOT/ide/prettier/prettierrc.json" "$HOME/.prettierrc" "prettier (ГЛОБАЛЬНО)"
    else
        plan_put "$ROOT/ide/$t" "$CONFIG/$t" "$t ($(layer_of "$t"))"
    fi
done

# ── печать плана ───────────────────────────────────────
head_ "план"
printf '  режим: %s · %s\n' \
    "$([ "$MODE" = link ] && echo 'симлинки на клон' || echo 'КОПИИ (обновление — явной командой)')" \
    "$([ "$APPLY" = 1 ] && echo 'ПРИМЕНЯЮ' || echo 'только показ')"
printf '\n'
for p in "${plan[@]}"; do
    IFS='|' read -r kind a b c <<<"$p"
    case "$kind" in
    ok) printf '  %s·%s %s\n' "$c_dim" "$c_off" "$b" ;;
    new) printf '  + %s → %s\n' "$b" "$a" ;;
    relink) printf '  ~ %s → %s\n' "$b" "$a" ;;
    backup) printf '  %s! %s УЕДЕТ в бэкап%s, на его место → %s\n' "$c_warn" "$b" "$c_off" "$a" ;;
    esac
done

if [ "${#backups[@]}" -gt 0 ]; then
    head_ "что будет сдвинуто"
    say "Это твоё. Ничего не удаляется — переносится в *.backup.<id>/value,"
    say "и './install.sh --uninstall' вернёт на место. Симлинк (stow, chezmoi)"
    say "переезжает стрелкой, то есть откат вернёт и её цель."
    for b in "${backups[@]}"; do say "$b"; done
fi

# чего НЕ будет: слои, которые не выбраны
unsel=""
for t in $(tools_in_layer contract) $(tools_in_layer slot) $(tools_in_layer taste) $(tools_in_layer global); do
    case " $selected " in *" $t "*) ;; *) unsel="$unsel $t" ;; esac
done
if [ -n "$unsel" ]; then
    head_ "не выбрано"
    for t in $unsel; do
        # Уже стоящее от прошлых установок надо называть вслух: иначе строка
        # «zenide их не трогает» читается как «их тут нет», а они есть.
        dst="$CONFIG/$t"
        [ "$t" = prettier ] && dst="$HOME/.prettierrc"
        if [ -L "$dst" ] && case "$(readlink "$dst")" in "$ROOT"/*) true ;; *) false ;; esac then
            printf '  %-9s %sуже стоит от прошлой установки — остаётся как есть%s\n' "$t" "$c_warn" "$c_off"
        else
            printf '  %-9s %s%s%s\n' "$t" "$c_dim" "$(breaks_of "$t")" "$c_off"
        fi
    done
    say ""
    say "Добавить: --with <тул>[,<тул>] | --with all | --with contract,slot"
    say "Свой конфиг ломать не обязательно: ide/<тул>/CONTRACT* — минимум,"
    say "который достаточно врезать в свой (его и проверяет zenide doctor)."
fi

if [ "$APPLY" != 1 ]; then
    printf '\n%sНичего не сделано.%s Применить: ./install.sh --apply\n' "$c_bold" "$c_off"
    exit 0
fi

# ── применение ─────────────────────────────────────────
head_ "применяю"
mkdir -p "$STATE" "$CONFIG" "$HOME/.local/bin"
record() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$MANIFEST"; }

put() { # put <источник> <назначение>
    local src="$1" dst="$2"
    if [ "$MODE" = copy ] && [ "$dst" != "$HOME/.local/bin/zenide" ]; then
        rm -rf "$dst" || return
        if [ "$src" = "$ROOT" ]; then
            # Только поставляемое ядро: без .git, тестов и временной песочницы.
            mkdir -p "$dst" || return
            cp -R "$ROOT/bin" "$ROOT/libexec" "$ROOT/modules" "$ROOT/ide" "$ROOT/profile" "$ROOT/VERSION" "$dst/" || return
        else
            cp -R "$src" "$dst" || return
        fi
        if [ "$dst" = "$ANCHOR" ]; then
            record keep "$dst"
        else
            local digest
            digest="$(fingerprint "$dst")" || return
            record copy "$dst" "$digest"
        fi
    else
        ln -sfn "$src" "$dst" || return
        record link "$dst" "$src"
    fi
}

for p in "${plan[@]}"; do
    IFS='|' read -r kind a b c <<<"$p"
    case "$kind" in
    ok) continue ;;
    new | relink)
        mkdir -p "$(dirname "$b")"
        put "$a" "$b"
        say "${c:-$b}"
        ;;
    backup)
        bak="$(mktemp -d "$b.backup.XXXXXXXX")/value"
        mv "$b" "$bak"
        record backup "$b" "$bak"
        say "$b → $bak"
        mkdir -p "$(dirname "$b")"
        put "$a" "$b"
        ;;
    esac
done

# личный профиль: примеры → реальные файлы, если их ещё нет. Кладём в тот
# каталог, который РЕАЛЬНО служит профилем, а не всегда в клон.
PROFILE_DIR="$ROOT/profile"
[ -d "$ANCHOR" ] && PROFILE_DIR="$(cd "$ANCHOR" && pwd -P)"
head_ "личный профиль ($PROFILE_DIR)"
for ex in profile/*.example; do
    [ -e "$ex" ] || continue
    real="$PROFILE_DIR/$(basename "${ex%.example}")"
    if [ -e "$real" ]; then
        say "$(basename "$real"): уже есть"
    else
        cp "$ex" "$real" && record keep "$real" && say "$(basename "$real"): создан из примера — заполни"
    fi
done

# Отметка версии ядра, под которую профиль собран. Нужна потому, что профиль
# живёт СНАРУЖИ клона: апстрим переименует слот или заведёт обязательный ключ,
# а внешний профиль молча останется со старым — в диффе это не всплывёт.
# Пишется один раз, при создании: иначе отметка всегда равна текущей версии и
# ничего не детектирует. Сверяет `zenide doctor`.
if [ ! -e "$PROFILE_DIR/.zenide-version" ]; then
    cp VERSION "$PROFILE_DIR/.zenide-version" 2>/dev/null &&
        record keep "$PROFILE_DIR/.zenide-version" &&
        say ".zenide-version: профиль помечен версией $(cat VERSION)"
fi

head_ "проверка"
"$ROOT/bin/zenide" doctor || true

printf '\nГотово. Манифест: %s\n' "$MANIFEST"
printf 'Откатить: ./install.sh --uninstall\n'
printf 'Перечитать tmux: tmux source-file %s/tmux.conf\n' "$CONFIG/tmux"
