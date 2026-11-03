#!/usr/bin/env sh
# Диагностика модуля для `zenide doctor`.
set -u

if command -v macism >/dev/null 2>&1 || [ -x /opt/homebrew/bin/macism ]; then
    printf 'macism найден — форс раскладки работает\n'
    exit 0
fi
printf 'нет macism → переходы НЕ переключают раскладку на ABC.\n'
printf '  brew install laishulu/homebrew/macism\n'
exit 1
