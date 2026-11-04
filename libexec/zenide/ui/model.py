"""Протокол отчёта и запуск проверок без изменения PATH окружением Python."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
import json
import os
from pathlib import Path
import signal


@dataclass(frozen=True)
class Check:
    id: str
    group: str
    group_title: str
    status: str
    title: str
    detail: str
    hint: str
    file: str


@dataclass(frozen=True)
class Report:
    root: str
    profile: str
    checks: tuple[Check, ...]
    exit_code: int

    @classmethod
    def parse(cls, raw: bytes, returncode: int) -> Report:
        try:
            data = json.loads(raw)
            if not isinstance(data, dict) or data.get("schema_version") != 1:
                raise ValueError("Неподдерживаемая версия отчёта")
            if returncode not in (0, 1) or data.get("exit_code") != returncode:
                raise ValueError("Код завершения не соответствует отчёту")
            if not all(isinstance(data.get(k), str) for k in ("root", "profile")):
                raise ValueError("В отчёте нет путей ядра и профиля")
            if not isinstance(data.get("checks"), list):
                raise ValueError("В отчёте нет списка проверок")
            checks = tuple(Check(**row) for row in data["checks"])
            if any(
                not all(isinstance(value, str) for value in vars(check).values())
                or check.status not in ("ok", "warn", "error", "info")
                for check in checks
            ):
                raise ValueError("Некорректные поля проверки")
            if len({check.id for check in checks}) != len(checks):
                raise ValueError("Повторяющиеся идентификаторы проверок")
            if bool(returncode) != any(check.status == "error" for check in checks):
                raise ValueError("Статусы проверок не соответствуют коду завершения")
            return cls(data["root"], data["profile"], checks, returncode)
        except (ValueError, TypeError, KeyError) as exc:
            raise ValueError(f"Не удалось прочитать отчёт doctor: {exc}") from exc


def dispatcher() -> Path:
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config / "zenide" / "bin" / "zenide"


async def collect(command: list[str], timeout: float = 30) -> Report:
    """Код 1 означает найденную проблему. Таймаут/отмена убивают всю группу."""
    process = await asyncio.create_subprocess_exec(
        *command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        start_new_session=True,
    )
    try:
        output, errors = await asyncio.wait_for(process.communicate(), timeout)
        if process.returncode not in (0, 1):
            message = errors.decode("utf-8", errors="replace").strip()
            raise ValueError(f"doctor завершился с кодом {process.returncode}: {message[:1000]}")
        return Report.parse(output, process.returncode)
    finally:
        # У потомка могли остаться свои дочерние процессы даже после его выхода.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        await process.wait()


def visible_checks(report: Report, query: str, problems_only: bool) -> list[Check]:
    words = query.casefold().split()
    return [
        check
        for check in report.checks
        if (not problems_only or check.status in ("warn", "error"))
        and all(
            word in " ".join(vars(check).values()).casefold()
            for word in words
        )
    ]
