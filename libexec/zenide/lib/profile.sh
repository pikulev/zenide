# Дефолты ядра и личный профиль поверх них. Сорсится диспетчером, поэтому
# доступно в любой подкоманде как ZENIDE_*.
#
# Фича-флагов здесь нет и не будет. Три разные сущности — три механизма:
#   · ВЫБОР из слота (какой git-TUI) — переменная ниже;
#   · ПОВЕДЕНИЕ с хуками (раскладка) — модуль, см. `modules`;
#   · ВОЗМОЖНОСТЬ среды (есть ли rga/bat/delta) — НЕ настройка: определяется
#     в рантайме через `command -v`. Флаг «у меня есть bat» был бы вторым
#     источником правды и протух бы в день установки bat.

# ── слоты: что чем реализовано ─────────────────────────
editor=helix     # кто редактор: каталог в libexec/zenide/editor/
git_tui=lazygit  # lazygit | gitui | tig
files=yazi       # файловый менеджер в постоянном окне
search=scooter   # search & replace по проекту

# ── включённые модули (пробелами) ──────────────────────
# Доступные — каталоги в modules/. Пусто = ядро без опционального поведения.
modules=""

# личный профиль перебивает всё выше
[ -r "$ZENIDE_PROFILE/modules.conf" ] && . "$ZENIDE_PROFILE/modules.conf"

export ZENIDE_EDITOR="$editor"
export ZENIDE_GIT_TUI="$git_tui"
export ZENIDE_FILES="$files"
export ZENIDE_SEARCH="$search"
export ZENIDE_MODULES="$modules"
