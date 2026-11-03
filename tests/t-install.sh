#!/usr/bin/env bash
# Поставка: что install.sh обещает, то и делает.
#
# Главное здесь — ОБРАТИМОСТЬ. Обещание «твои конфиги не пострадают» без теста
# стоит ровно ничего: оно ломается молча и выясняется на чужой машине. Правило
# проекта — свойство безопасности без теста в README не обещается.
#
# Всё крутится на КОПИИ репозитория и в поддельном $HOME: ни рабочее дерево,
# ни настоящий ~/.config не трогаются.
set -u
. "$(dirname "$0")/lib.sh"

echo "t-install: установка, откат, границы"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zenide-inst.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
CLONE="$WORK/zenide"
H="$WORK/home"

cp -R "$REPO_ROOT" "$CLONE"
rm -rf "$CLONE/.sandbox"
# Установщик должен работать и из архива без истории Git.
rm -rf "$CLONE/.git"
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME ZENIDE_PROFILE

mkdir -p "$H/.config/helix"
printf 'theme = "gruvbox"\n[editor]\nline-number = "relative"\n' >"$H/.config/helix/config.toml"
MINE="$(shasum "$H/.config/helix/config.toml" | cut -d' ' -f1)"

run() { HOME="$H" "$CLONE/install.sh" "$@" >/dev/null 2>&1; }
count_home() { find "$H" -mindepth 1 2>/dev/null | wc -l | tr -d ' '; }

# ── 1. без аргументов НИЧЕГО не делает ─────────────────
# Это умолчание и есть главное обещание безопасности.
before="$(count_home)"
run --with all
assert_eq "dry-run не создал ни одного файла" "$(count_home)" "$before"

MANIFEST="$H/.local/state/zenide/manifest"
[ -e "$MANIFEST" ] && t_fail "dry-run записал манифест" || t_ok "dry-run не записал манифест"

# ── 2. --apply ставит ядро и только его ────────────────
run --apply
[ -L "$H/.config/tmux" ] && t_ok "ядро: ~/.config/tmux слинкован" || t_fail "ядро: нет симлинка tmux"
[ -L "$H/.config/zenide" ] && t_ok "ядро: ~/.config/zenide слинкован" || t_fail "ядро: нет симлинка zenide"
[ -L "$H/.config/zenide-profile" ] && t_ok "якорь профиля поставлен" || t_fail "нет якоря профиля"
[ -e "$MANIFEST" ] && t_ok "манифест записан" || t_fail "манифеста нет"

# невыбранный сосед не тронут — у человека остался ЕГО конфиг
assert_eq "невыбранный helix остался твоим" \
    "$(shasum "$H/.config/helix/config.toml" | cut -d' ' -f1)" "$MINE"

# ── 3. выбранный сосед: чужое уезжает в бэкап ──────────
run --with helix --apply
[ -L "$H/.config/helix" ] && t_ok "выбранный helix слинкован" || t_fail "helix не слинкован"
baks="$(find "$H/.config" -maxdepth 1 -name 'helix.backup.*' | wc -l | tr -d ' ')"
assert_eq "твой helix уехал в бэкап" "$baks" "1"

# ── 4. профиль: апстрим пишет туда только примеры ──────
# Профиль — территория пользователя. Если установщик кладёт туда что-то ещё,
# обещание «git pull не конфликтует» становится ложным.
prof="$CLONE/profile"
unexpected=""
for f in "$prof"/*; do
    b="$(basename "$f")"
    case "$b" in
    *.conf | *.example | *.local | .zenide-version) ;;
    *) unexpected="$unexpected $b" ;;
    esac
done
assert_eq "install не создал в профиле ничего лишнего" "${unexpected# }" ""
[ -e "$prof/.zenide-version" ] && t_ok "профиль помечен версией ядра" || t_fail "нет .zenide-version"

# ── 5. ОТКАТ возвращает чужое побайтово ────────────────
run --uninstall
assert_eq "откат вернул твой helix побайтово" \
    "$(shasum "$H/.config/helix/config.toml" 2>/dev/null | cut -d' ' -f1)" "$MINE"
[ -L "$H/.config/tmux" ] && t_fail "откат оставил симлинк tmux" || t_ok "откат снял симлинк tmux"
[ -L "$H/.config/zenide" ] && t_fail "откат оставил симлинк zenide" || t_ok "откат снял симлинк zenide"
left="$(find "$H" -maxdepth 3 -name '*.backup.*' | wc -l | tr -d ' ')"
assert_eq "бэкапов не осталось" "$left" "0"
[ -e "$MANIFEST" ] && t_fail "манифест пережил откат" || t_ok "манифест убран"

# ── 6. --copy: реальные каталоги, клон не протекает ────
run --copy --apply
[ -L "$H/.config/tmux" ] && t_fail "--copy сделал симлинк" || t_ok "--copy сделал реальный каталог"
echo "# протечка" >>"$CLONE/ide/tmux/tmux.conf"
if grep -q "# протечка" "$H/.config/tmux/tmux.conf" 2>/dev/null; then
    t_fail "правка в клоне протекла в копию"
else
    t_ok "копия независима от клона"
fi
cp "$REPO_ROOT/ide/tmux/tmux.conf" "$CLONE/ide/tmux/tmux.conf"

# ── 7. работающая команда и сохранение правок в установленной копии ──
out="$(HOME="$H" "$H/.local/bin/zenide" version 2>&1)"
assert_has "CLI --copy находит установленное ядро" "$out" "$H/.config/zenide"
printf '# пользовательская правка\n' >> "$H/.config/tmux/tmux.conf"
run --uninstall
saved="$(find "$H/.config" -path '*/tmux.saved.*/value/tmux.conf' | head -1)"
[ -n "$saved" ] && grep -q 'пользовательская правка' "$saved" \
    && t_ok "откат сохранил изменённую копию" || t_fail "откат потерял правку копии"

# Повторные установки разматываются до исходного пользовательского конфига.
run --copy --with helix --apply
run --copy --with helix --apply
run --uninstall
assert_eq "две копирующие установки вернули исходный helix" \
    "$(shasum "$H/.config/helix/config.toml" | cut -d' ' -f1)" "$MINE"
assert_eq "после повторных установок не осталось бэкапов" \
    "$(find "$H" -name '*.backup.*' | wc -l | tr -d ' ')" 0

# ── 8. ЧУЖОЙ симлинк: сдвигается в бэкап, откат возвращает стрелку ─────
# Кейс «переезжаю со своих дотфайлов»: у stow/chezmoi/yadm на месте конфига
# лежит СИМЛИНК, а не каталог. `ln -sfn` затёр бы его без следа — цель чужой
# стрелки не записана больше нигде, и откат вернуть её не смог бы.
# Отдельный поддельный $HOME: состояние предыдущих кейсов здесь только мешает.
H2="$WORK/home2"
mkdir -p "$H2/.config" "$H2/dotfiles/helix"
printf 'theme = "stow"\n' >"$H2/dotfiles/helix/config.toml"
ln -s "$H2/dotfiles/helix" "$H2/.config/helix"
ln -s "$H2/dotfiles/gone" "$H2/.config/yazi" # БИТЫЙ: цели не существует

out="$(HOME="$H2" "$CLONE/install.sh" --with helix,yazi 2>&1)"
assert_has "план предупреждает о чужом симлинке" "$out" "УЕДЕТ в бэкап"

HOME="$H2" "$CLONE/install.sh" --with helix,yazi --apply >/dev/null 2>&1
bak="$(find "$H2/.config" -maxdepth 1 -name 'helix.backup.*' | head -1)"
assert_eq "в бэкапе лежит ТВОЯ стрелка, а не копия каталога" \
    "$(readlink "$bak/value" 2>/dev/null)" "$H2/dotfiles/helix"

HOME="$H2" "$CLONE/install.sh" --uninstall >/dev/null 2>&1
assert_eq "откат вернул чужую стрелку" \
    "$(readlink "$H2/.config/helix" 2>/dev/null)" "$H2/dotfiles/helix"
# Битый симлинк — отдельный кейс: на нём `-e` ложь, и проход 2 отката без
# парной проверки `-L` молча прошёл бы мимо.
assert_eq "откат вернул и БИТЫЙ симлинк" \
    "$(readlink "$H2/.config/yazi" 2>/dev/null)" "$H2/dotfiles/gone"

# Подмена установленного пути пользователем не даёт права удалить новое.
HOME="$H2" "$CLONE/install.sh" --with helix --apply >/dev/null 2>&1
rm "$H2/.config/helix"
mkdir "$H2/.config/helix"
printf 'replacement\n' > "$H2/.config/helix/config.toml"
HOME="$H2" "$CLONE/install.sh" --uninstall >/dev/null 2>&1
saved="$(find "$H2/.config" -path '*/helix.saved.*/value/config.toml' | head -1)"
assert_eq "подменённый каталог сохранён" "$(cat "$saved")" replacement
assert_eq "исходная стрелка возвращена после подмены" "$(readlink "$H2/.config/helix")" "$H2/dotfiles/helix"

# Созданный и заполненный профиль переживает откат.
HP="$WORK/home-profile"
mkdir -p "$HP/.config/zenide-profile"
HOME="$HP" "$CLONE/install.sh" --apply >/dev/null 2>&1
printf 'personal-data\n' > "$HP/.config/zenide-profile/git.local"
HOME="$HP" "$CLONE/install.sh" --uninstall >/dev/null 2>&1
assert_eq "личный файл профиля сохранён на месте" "$(cat "$HP/.config/zenide-profile/git.local")" personal-data

# Старые манифесты без отпечатков не дают права удалить неизвестную копию.
mkdir -p "$HP/.local/state/zenide" "$HP/.config/legacy"
printf 'legacy-edit\n' > "$HP/.config/legacy/config"
printf 'copy\t%s\t\n' "$HP/.config/legacy" > "$HP/.local/state/zenide/manifest"
HOME="$HP" "$CLONE/install.sh" --uninstall >/dev/null 2>&1
saved="$(find "$HP/.config" -path '*/legacy.saved.*/value/config' | head -1)"
assert_eq "копия из старого манифеста сохранена" "$(cat "$saved")" legacy-edit

# Отсутствующий бэкап — ошибка, а журнал нужен для восстановления.
mkdir -p "$HP/.local/state/zenide"
printf 'backup\t%s\t%s\n' "$HP/.config/missing" "$HP/absent" > "$HP/.local/state/zenide/manifest"
HOME="$HP" "$CLONE/install.sh" --uninstall >/dev/null 2>&1
assert_eq "отсутствующий бэкап останавливает откат" "$?" 1
[ -s "$HP/.local/state/zenide/manifest" ] && t_ok "ошибка не уничтожила журнал" || t_fail "ошибка уничтожила журнал"

# ── 9. слой global: только поимённо, и тоже обратим ────
# `global` меняет поведение ЗА пределами IDE (git, prettier, версии рантаймов
# у mise), поэтому в `--with all` он не входит. Это обещание из LAYERS, и без
# теста оно ломается молча: достаточно опечатки в списке слоёв, и чужой
# ~/.config/mise уедет в бэкап у человека, который просил «всё, кроме global».
H4="$WORK/home4"
mkdir -p "$H4/.config/mise"
printf '[tools]\nnode = "20"\n' >"$H4/.config/mise/config.toml"
MINE4="$(shasum "$H4/.config/mise/config.toml" | cut -d' ' -f1)"

HOME="$H4" "$CLONE/install.sh" --with all --apply >/dev/null 2>&1
[ -L "$H4/.config/mise" ] && t_fail "--with all затронул слой global" \
    || t_ok "--with all не тронул global"
assert_eq "чужой конфиг mise цел после --with all" \
    "$(shasum "$H4/.config/mise/config.toml" | cut -d' ' -f1)" "$MINE4"

HOME="$H4" "$CLONE/install.sh" --with mise --apply >/dev/null 2>&1
[ -L "$H4/.config/mise" ] && t_ok "поимённый --with mise слинкован" \
    || t_fail "--with mise не слинковал"

HOME="$H4" "$CLONE/install.sh" --uninstall >/dev/null 2>&1
assert_eq "откат вернул чужой конфиг mise побайтово" \
    "$(shasum "$H4/.config/mise/config.toml" 2>/dev/null | cut -d' ' -f1)" "$MINE4"
left4="$(find "$H4" -maxdepth 3 -name '*.backup.*' | wc -l | tr -d ' ')"
assert_eq "бэкапов слоя global не осталось" "$left4" "0"

# ── 10. контракты не разошлись с полными конфигами ─────
# CONTRACT — выжимка из соседнего конфига. Разъедутся молча: doctor проверяет
# только helix и yazi, остальное никто не ловит.
for c in "$CLONE"/ide/*/CONTRACT*; do
    [ -e "$c" ] || continue
    tool="$(basename "$(dirname "$c")")"
    full=""
    for cand in "$CLONE/ide/$tool"/*; do
        case "$(basename "$cand")" in CONTRACT*) continue ;; esac
        [ -f "$cand" ] && full="$full $cand"
    done
    missing=0
    while IFS= read -r line; do
        # комментарии бывают с отступом (внутри блоков yaml/toml) — срезаем
        # ведущие пробелы ПЕРЕД проверкой, иначе они уедут в сравнение
        bare="${line#"${line%%[![:space:]]*}"}"
        case "$bare" in '' | '#'*) continue ;; esac
        grep -qF -- "$line" $full 2>/dev/null || {
            missing=1
            printf '       нет в конфиге %s: %s\n' "$tool" "$line" >&2
        }
    done <"$c"
    [ "$missing" -eq 0 ] &&
        t_ok "контракт $tool совпадает с его конфигом" ||
        t_fail "контракт $tool разошёлся с конфигом"
done

exit "$FAILED"
