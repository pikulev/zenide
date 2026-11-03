#!/usr/bin/env bash
# Записать демо-GIF для README: ./docs/demo/record.sh
#
# Как это работает, если без записи непонятно. Нужен pty: asciinema пишет то,
# что видит терминал, а терминала у неинтерактивного процесса нет. Поэтому
# задействованы ДВА tmux-сокета:
#   · внутренний (demo) — то, что попадёт в кадр;
#   · внешний (rec) — его пейн даёт asciinema нужный pty, а внутри пейна
#     asciinema пишет клиента, прицепленного к внутренней сессии.
# Живые сессии (сокет default) не трогаются.
#
# ВАЖНО, иначе ничего не работает: клавиши шлём ВО ВНЕШНИЙ пейн, а не во
# внутренний. `send-keys` отдаёт байты программе в пейне, а не самому tmux,
# поэтому префикс во внутреннем пейне просто уходит в шелл. Во внешнем пейне
# сидит прицепленный клиент — для него это ввод с клавиатуры, и префикс
# отрабатывает, как у человека.
#
# Фикстура своя: нейтральные имена и два автора в истории, иначе blame покажет
# одно имя, а в кадр попадут настоящие проекты.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
DEMO_DIR="$PWD"

command -v asciinema >/dev/null || { echo 'нет asciinema: brew install asciinema'; exit 1; }
command -v agg       >/dev/null || { echo 'нет agg: brew install agg'; exit 1; }

OUT_SOCK=zenide-rec-out
IN_SOCK=zenide-rec-in
# Имя сессии попадает в левый край бара, поэтому называем его проектом.
# Фикстура лежит в домашнем каталоге: в кадре виден промпт, и `~/payments`
# читается как настоящий проект. /tmp не годится — на macOS это симлинк, и
# tmux подставляет развёрнутый `/private/tmp/...`, а mktemp-путь вида
# /var/folders/zp/67kk… выглядит как мусор.
SESSION=payments
# Два проекта в общем корне: без второго нечего показывать переключателю.
WORK="$HOME/work"
FIX_PATH="$WORK/payments"
# Профиль ВНЕ $WORK: переключатель проектов перечисляет подкаталоги корня, и
# служебная папка попадала в список наравне с проектами.
PROFILE_PATH=""
COLS=120
ROWS=32
FIX=""

# ── человекоподобный ритм ──────────────────────────────
# Пауза перед нажатием: без неё запись выглядит так, будто клавиши жмёт робот,
# и глаз не успевает прочитать, что изменилось на экране.
beat()  { sleep "${1:-0.9}"; }
key()   { tmux -L "$OUT_SOCK" send-keys -t rec "$@"; beat 0.7; }
# Печать по символу: показываем, что строка набирается, а не вставляется.
type_() {
    local s="$1" i ch
    for i in $(seq 1 ${#s}); do
        ch="${s:i-1:1}"
        # Голый «;» tmux считает разделителем команд ДАЖЕ с -l: без экранирования
        # символ молча пропадает, и в кадре остаётся строка без точки с запятой.
        [ "$ch" = ";" ] && ch='\;'
        tmux -L "$OUT_SOCK" send-keys -t rec -l "$ch"
        sleep 0.08
    done
    beat 0.6
}
prefix() { key C-Space; }

# Закрыть попап и УБЕДИТЬСЯ, что он закрылся. Одного Escape мало: у blame
# внутри есть вложенные виды (история строки по C-l), и первый Escape лишь
# возвращает в список. Если не проверить, все последующие нажатия молча
# уходят в фильтр попапа, а сцена дальше идёт вхолостую.
close_popup() { # close_popup <подстрока-признак попапа>
    local pat="$1" i
    for i in 1 2 3; do
        key Escape
        sleep 0.8
        tmux -L "$OUT_SOCK" capture-pane -p -t rec | grep -qF -- "$pat" || return 0
    done
    printf '  ⚠ попап не закрылся: %s\n' "$pat" >&2
    return 1
}

# Дождаться, пока ожидаемое из кадра ИСЧЕЗНЕТ. Нужно там, где сцена идёт
# дальше только после закрытия окна или попапа.
wait_gone() { # wait_gone <подстрока> [секунд]
    local pat="$1" limit="${2:-10}"
    for _ in $(seq 1 $((limit * 4))); do
        tmux -L "$OUT_SOCK" capture-pane -p -t rec | grep -qF -- "$pat" || return 0
        sleep 0.25
    done
    return 1
}

# Дождаться, пока в КАДРЕ появится ожидаемое, и только потом идти дальше.
# Слепые sleep тут не годятся: попап blame сначала спрашивает у редактора
# текущую строку (поллинг временного файла), потом зовёт git и bat, и на
# холодном ФС это занимает заметно дольше, чем на прогретом. Если не дождаться,
# сцена уедет вперёд и в запись попадёт пустой экран.
wait_screen() { # wait_screen <подстрока> [секунд]
    local pat="$1" limit="${2:-15}" i
    for i in $(seq 1 $((limit * 4))); do
        tmux -L "$OUT_SOCK" capture-pane -p -t rec | grep -qF -- "$pat" && return 0
        sleep 0.25
    done
    printf '  ⚠ не дождался в кадре: %s\n' "$pat" >&2
    return 1
}

# ── фикстура ───────────────────────────────────────────
make_fixture() {
    # Каталог создаётся и сносится скриптом, поэтому чужой не трогаем.
    if [ -e "$WORK" ] && [ ! -f "$WORK/.zenide-demo" ]; then
        printf 'отказ: %s существует и создан не мной\n' "$WORK" >&2
        exit 1
    fi
    rm -rf "$WORK"
    mkdir -p "$WORK"
    : > "$WORK/.zenide-demo"     # метка «каталог мой, сносить можно»
    FIX="$FIX_PATH"

    # ── проект в кадре ────────────────────────────────
    mkdir -p "$FIX/src"
    git init -q "$FIX"
    cat > "$FIX/src/payment.ts" <<'TS'
export function applyDiscount(total: number, percent: number) {
  const factor = 1 - percent / 100;
  return Math.round(total * factor);
}

export function payable(total: number) {
  return applyDiscount(total, 10);
}
TS
    # второй файл с тем же вызовом: иначе поиску нечего показывать списком
    cat > "$FIX/src/checkout.ts" <<'TS'
import { applyDiscount } from "./payment";

export function checkoutTotal(items: number[]) {
  const sum = items.reduce((a, b) => a + b, 0);
  return applyDiscount(sum, 10);
}
TS
    cat > "$FIX/README.md" <<'MD'
# payments

Расчёт скидок и итоговой суммы заказа.
MD
    git -C "$FIX" add -A
    git -C "$FIX" -c user.email=alice@example.com -c user.name="Alice Ivanova" \
        commit -qm "расчёт скидки"
    # вторая правка от другого автора: иначе blame одноцветный
    sed -i '' 's|percent / 100;|percent / 100.0;|' "$FIX/src/payment.ts"
    git -C "$FIX" add -A
    git -C "$FIX" -c user.email=bob@example.com -c user.name="Bob Petrov" \
        commit -qm "починить деление"

    # ── соседний проект: нужен только переключателю ───
    mkdir -p "$WORK/notes"
    git init -q "$WORK/notes"
    printf '# заметки\n' > "$WORK/notes/README.md"
    git -C "$WORK/notes" add -A
    git -C "$WORK/notes" -c user.email=t@example.com -c user.name=t commit -qm "начало"

    # ── профиль: переключатель должен видеть ТОЛЬКО фикстуру ──
    PROFILE_PATH="$(mktemp -d "${TMPDIR:-/tmp}/zenide-demo-profile.XXXXXX")"
    # Иначе в кадр попадут настоящие репозитории владельца.
    cat > "$PROFILE_PATH/projects.conf" <<EOF
roots=("$WORK")
standalone=()
containers=()
EOF
    cat > "$PROFILE_PATH/modules.conf" <<'EOF'
editor=helix
git_tui=lazygit
files=yazi
search=scooter
modules=""
EOF
}

# ── сессия в кадре ─────────────────────────────────────
start_inner() {
    tmux -L "$IN_SOCK" kill-server 2>/dev/null
    # -f конфига проекта: в кадре должен быть настоящий сетап, а не дефолт tmux
    tmux -L "$IN_SOCK" -f "$HOME/.config/tmux/tmux.conf" \
        new-session -d -s "$SESSION" -c "$FIX" -x "$COLS" -y "$ROWS" \
            -e "ZENIDE_PROFILE=$PROFILE_PATH"
    # по умолчанию сообщения tmux жёлтые на чёрном и читаются как ошибка;
    # приглушаем до тона бара, чтобы реплики выглядели закадровым текстом
    tmux -L "$IN_SOCK" set -g message-style "bg=#525053,fg=#f7f1ff"
    sleep 1.5
}

# Поднять hx и дождаться статусбара: фиксированный sleep тут не годится,
# старт плавает из-за LSP.
wait_hx() {
    local _ w
    for _ in $(seq 1 60); do
        w="$(tmux -L "$IN_SOCK" list-windows -t "$SESSION" -F '#{window_id} #{window_name}' \
             | awk '$2 == "hx" { print $1 }')"
        [ -n "$w" ] && tmux -L "$IN_SOCK" capture-pane -p -t "$w" | grep -q 'NOR' && return 0
        sleep 0.25
    done
    return 1
}

# Отрезать хвост записи по ВРЕМЕНИ. Когда запись закрывается, прицепленный
# клиент выходит из alternate screen и чистит экран — последним кадром GIF
# оказывается пустота, то есть именно то, что видно на превью. Обрезать по
# самой escape-последовательности нельзя: helix и fzf входят в alt screen и
# выходят из него по многу раз за сцену. А вот момент окончания сцены скрипт
# знает точно, поэтому режем по нему.
trim_cast() { # trim_cast <файл.cast> <секунд от начала>
    python3 - "$1" "$2" <<'PYEOF'
import json, sys
path, limit = sys.argv[1], float(sys.argv[2])
lines = open(path).read().rstrip("\n").split("\n")
out, clock = [lines[0]], 0.0
for line in lines[1:]:
    if not line.startswith("["):
        continue
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    clock += ev[0]
    if clock > limit:
        break
    out.append(line)
open(path, "w").write("\n".join(out) + "\n")
PYEOF
}

# ── запись ─────────────────────────────────────────────
record() { # record <имя-сцены> <функция-сценария>
    local name="$1" scene="$2"
    local cast="$DEMO_DIR/$name.cast"
    printf '\n== %s ==\n' "$name"
    make_fixture
    start_inner

    tmux -L "$OUT_SOCK" kill-server 2>/dev/null
    tmux -L "$OUT_SOCK" -f /dev/null new-session -d -s rec -x "$COLS" -y "$ROWS"
    tmux -L "$OUT_SOCK" send-keys -t rec \
        "asciinema rec '$cast' --overwrite -c 'tmux -L $IN_SOCK attach -t $SESSION'" Enter
    sleep 3
    local t0=$SECONDS

    "$scene"

    beat 1.2
    local span=$((SECONDS - t0))
    # Завершаем запись ДЕТАЧЕМ клиента, а не C-d: Ctrl-D долетел бы до
    # приложения в пейне раньше, чем до asciinema, и helix понял бы его как
    # «страница вниз» — в последнем кадре курсор уезжал в конец файла.
    tmux -L "$OUT_SOCK" send-keys -t rec C-Space
    sleep 0.3
    tmux -L "$OUT_SOCK" send-keys -t rec d
    sleep 2
    tmux -L "$OUT_SOCK" kill-server 2>/dev/null
    tmux -L "$IN_SOCK" kill-server 2>/dev/null
    rm -rf "$WORK" "$PROFILE_PATH"
    [ -s "$cast" ] || { echo "  ⚠ запись пустая"; return 1; }
    trim_cast "$cast" "$span"
    # idle-time-limit режет паузы, которых я насыпал для читаемости, но
    # оставляет ритм; speed чуть ускоряет набор. fps-cap 10: терминал почти
    # статичен, дефолтные 30 кадров/с раздувают GIF без видимой разницы
    agg --theme monokai --font-size 16 --idle-time-limit 1.2 --speed 1.15 \
        --fps-cap 10 "$cast" "$DEMO_DIR/$name.gif" 2>&1 | tail -1
    printf '  готово: %s (%s)\n' "$name.gif" \
        "$(du -h "$DEMO_DIR/$name.gif" | cut -f1 | tr -d ' ')"
}

# ── сцена ──────────────────────────────────────────────
# Один связный рабочий эпизод, который проходит по всему списку возможностей
# из README. Так видно и клавиши, и то, ради чего они.
#
# Реплики идут через `display-message`: они занимают строку статуса и читаются
# закадровым комментарием. Висят ДОЛЬШЕ, чем пауза под ними, поэтому текст
# ещё на экране, когда начинается действие, — иначе глаз не успевает связать
# слова с тем, что происходит.
say() { # say <текст> [секунд паузы]
    local sec="${1:+${2:-3}}"
    # bash не умеет дробную арифметику, миллисекунды считает awk. Держим
    # сообщение вдвое дольше паузы: оно должно пережить начало действия.
    tmux -L "$IN_SOCK" display-message \
        -d "$(awk -v s="$sec" 'BEGIN{printf "%d", s*2200}')" "  $1"
    sleep "$sec"
}

scene_session() {
    beat 1.5

    # ── 🪟 проекты ─────────────────────────────────────
    say "проект это сессия: переключаемся фаззи-поиском" 4
    prefix; key f
    beat 2.5
    type_ "payme"
    beat 2
    key Enter
    beat 3

    # ── 🧭 шпаргалка ───────────────────────────────────
    say "забыл клавишу? C-Space ? покажет весь сетап" 4
    prefix; key '?'
    wait_screen "проекты"
    beat 2.5
    type_ "git"
    beat 3
    close_popup "keys ❯"
    beat 1.5

    # ── 🔍 найти файл ──────────────────────────────────
    say "файл ищем по имени, а не набираем путь" 3.5
    prefix; key o
    wait_screen "payment.ts"
    beat 1
    type_ "payme"
    beat 1.5
    key Enter
    wait_hx
    wait_screen "applyDiscount"
    beat 2

    # ── 🕰 кто написал строку ──────────────────────────
    say "ставим курсор на захардкоженную десятку" 3.5
    key Down; key Down; key Down; key Down; key Down; key Down
    beat 2
    say "и спрашиваем: кто её добавил и в каком коммите" 4
    prefix; key B
    wait_screen "Alice"
    beat 5                     # дать прочитать дифф коммита в превью
    say "сверху дифф того самого коммита" 4
    beat 3
    say "C-l — история ИМЕННО этой строки, сквозь переименования" 4.5
    key C-l
    beat 5
    close_popup "blame ❯"
    beat 2

    # ── 🔎 найти текст по проекту ──────────────────────
    say "а где ещё зовут applyDiscount? ищем по всему проекту" 4
    prefix; key /
    beat 1
    type_ "applyDiscount"
    beat 3.5
    say "четыре совпадения в двух файлах. уточняем запрос" 4
    # Уточняем вместо навигации по списку: rga отдаёт совпадения асинхронно,
    # порядок между прогонами не фиксирован, и выбор «вторым сверху» ехал бы
    # от записи к записи.
    type_ '\(sum'
    beat 3
    key Enter
    wait_hx
    wait_screen "checkoutTotal" 20
    beat 2.5

    # ── ✏️ правка ──────────────────────────────────────
    say "та же десятка и здесь. вынесем её в константу" 4
    # Выделяем строку целиком и набираем заново: точечные движения (f, miw)
    # по send-keys отрабатывают через раз.
    key x
    beat 1
    key c
    beat 0.8
    type_ "return applyDiscount(sum, DEFAULT_DISCOUNT);"
    beat 1.2
    key Escape
    beat 0.8
    type_ ":w"; key Enter
    beat 2

    # ── 📦 дифф ханка ──────────────────────────────────
    say "смотрим дифф ханка прямо под курсором" 4
    prefix; key D
    beat 5
    key q
    beat 1.5

    # ── 🗂 файловый менеджер ───────────────────────────
    say "заглавная E — файловый менеджер НА каталоге этого файла" 4.5
    prefix; key E
    wait_screen "checkout.ts"
    beat 4

    # ── ✏️ замена по проекту ───────────────────────────
    say "замена по всему проекту — отдельным окном" 4
    prefix; key R
    beat 5
    prefix; key Enter          # назад в редактор
    beat 2

    # ── ⚡️ разовая команда ─────────────────────────────
    say "разовая команда, не теряя контекст" 3.5
    prefix; key Space
    beat 2
    # НЕ `git log`: он уходит в пейджер (delta), и следующий `exit` улетает
    # в less, а не в шелл — попап остаётся открытым, и вся сцена дальше идёт
    # вхолостую. `git status -sb` пейджер не поднимает.
    type_ "git status -sb"
    key Enter
    beat 4
    type_ "exit"; key Enter
    wait_gone "payments ❯" 10 || true
    beat 2

    # ── 🤖 агент рядом ─────────────────────────────────
    say "агент живёт обычным окном и правит файлы на диске" 4.5
    prefix; key c
    beat 1.5
    type_ "sed -i '' 's/DEFAULT_DISCOUNT/15/' src/checkout.ts"
    key Enter
    beat 2
    say "вернулись в редактор — буфер уже перечитан" 4
    prefix; key Enter
    wait_screen ", 15)" 20
    beat 3

    # ── 📦 git ─────────────────────────────────────────
    say "дальше обычный git-клиент: правка уже видна" 4
    prefix; key g
    beat 5
    say "всё это время редактор не перезапускался" 4
}

record demo scene_session
