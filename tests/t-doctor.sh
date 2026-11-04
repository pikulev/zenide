#!/usr/bin/env bash
# JSON, текст и аварийный запуск без Textual; проверки в отдельном HOME.
set -eu
cd "$(dirname "$0")/.."
if ! command -v python3 >/dev/null 2>&1; then
    printf '  skip doctor: для проверки JSON нужен python3\n'
    exit 0
fi
python3 tests/test_doctor.py
