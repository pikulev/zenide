# tig — редактор задаём через TIG_EDITOR (приоритетнее GIT_EDITOR/core.editor,
# и действует только на tig — глобальный git не трогаем).
#
# Обёртка hx-goto.sh переводит vi-стиль "+N файл" (как tig зовёт редактор при
# editor-line-number=yes) в то, что понимает helix. Внутри tmux файл уходит в
# УЖЕ работающий hx (`zenide open`) — в отличие от gitui, здесь это безопасно:
# tig редактор для сообщений коммитов не зовёт, только для открытия файлов.
export TIG_EDITOR="${ZENIDE_ROOT:-$HOME/.config/zenide}/ide/tig/hx-goto.sh"
