#!/usr/bin/env bash
# Опциональное окружение живёт вне клона: --copy не переносит виртуальную среду.
set -eu

ui_python="${XDG_DATA_HOME:-$HOME/.local/share}/zenide/doctor-venv/bin/python"
if [ ! -x "$ui_python" ] || ! "$ui_python" -c 'import textual' >/dev/null 2>&1; then
    printf 'Для doctor --ui нужно опциональное окружение Textual.\n\n'
    printf 'Установить (нужны uv и Python ≥ 3.11):\n'
    printf '  UV_PROJECT_ENVIRONMENT="${XDG_DATA_HOME:-$HOME/.local/share}/zenide/doctor-venv" \\\n'
    printf '    uv sync --locked --no-python-downloads --project "%s/ui"\n\n' "$ZENIDE_LIBEXEC"
    printf 'Текстовая диагностика доступна: zenide doctor\n'
    if [ -t 0 ]; then read -r -n 1 -p 'Нажми любую клавишу…' || :; printf '\n'; fi
    exit 2
fi
if [ ! -t 0 ] || [ ! -t 1 ]; then
    printf 'doctor --ui нужен терминал; для автоматизации используй doctor --json.\n' >&2
    exit 2
fi
exec "$ui_python" "$ZENIDE_LIBEXEC/ui/doctor_ui.py"
