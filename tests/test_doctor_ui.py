"""Навигация, ошибки и отмена проверок в Textual без живого tmux."""

import asyncio
from dataclasses import asdict
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from textual.widgets import Button, Checkbox, DataTable, Input, Static

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "libexec/zenide/ui"))

# Тестируем исходники без установки собственного Python-пакета.
from doctor_ui import DoctorApp  # noqa: E402
from model import Check, Report, collect  # noqa: E402


def fixture_report():
    return Report(str(REPO), str(REPO / "profile"), (
        Check("rga", "optional", "Возможности", "warn", "rga", "C-Space / — поиск [red]", "brew install ripgrep-all", ""),
        Check("profile", "profile", "Профиль", "info", "Профиль", "Личный профиль", "Открой конфиг", str(REPO / "profile/modules.conf")),
        Check("tmux", "required", "Обязательное", "ok", "tmux", "Найден", "", ""),
    ), 0)


class ModelTests(unittest.IsolatedAsyncioTestCase):
    async def test_error_exit_is_a_valid_report(self):
        report = fixture_report()
        data = asdict(report)
        data["schema_version"] = 1
        data["checks"][0]["status"] = "error"
        data["exit_code"] = 1
        raw = json.dumps(data).encode()
        self.assertEqual(Report.parse(raw, 1).checks[0].status, "error")
        with self.assertRaises(ValueError):
            Report.parse(raw, 0)
        with self.assertRaises(ValueError):
            Report.parse(b"not json", 0)

    async def test_timeout_and_cancellation_stop_descendants(self):
        for cancel in (False, True):
            with self.subTest(cancel=cancel), tempfile.TemporaryDirectory() as directory:
                pidfile = Path(directory) / "child.pid"
                task = asyncio.create_task(collect(
                    ["/bin/sh", "-c", 'sleep 60 & echo $! > "$1"; wait', "test", str(pidfile)],
                    timeout=2 if cancel else 0.4,
                ))
                for _ in range(100):
                    if pidfile.exists() and pidfile.read_text().strip():
                        break
                    await asyncio.sleep(0.01)
                self.assertTrue(pidfile.exists())
                if cancel:
                    task.cancel()
                with self.assertRaises(asyncio.CancelledError if cancel else TimeoutError):
                    await task
                pid = pidfile.read_text().strip()
                status = subprocess.run(["ps", "-p", pid, "-o", "stat="], capture_output=True, text=True).stdout.strip()
                self.assertTrue(not status or status.startswith("Z"), status)


class UiTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, ZENIDE_ROOT=str(REPO), ZENIDE_PROFILE=str(REPO / "profile"))
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.loader = patch("doctor_ui.collect", new_callable=AsyncMock)
        self.collect = self.loader.start()
        self.addCleanup(self.loader.stop)
        self.collect.return_value = fixture_report()

    async def test_search_filter_selection_refresh_and_small_screen(self):
        app = DoctorApp()
        async with app.run_test(size=(120, 35)) as pilot:
            await app.workers.wait_for_complete()
            await pilot.pause()
            table = app.query_one(DataTable)
            self.assertEqual(table.row_count, 3)
            self.assertIn("[red]", str(app.query_one("#detail", Static).content))
            await pilot.press("ctrl+p")
            self.assertTrue(app.query_one(Checkbox).value)
            self.assertEqual(table.row_count, 1)
            await pilot.press("slash")
            await pilot.press(*list("absent"))
            self.assertEqual(table.row_count, 0)
            self.assertIsNone(app.selected)
            self.assertTrue(app.query_one("#open", Button).disabled)
            app.query_one(Input).value = ""
            await pilot.press("escape", "ctrl+p", "down")
            self.assertEqual(app.selected.id, "profile")
            self.assertFalse(app.query_one("#open", Button).disabled)
            await pilot.press("ctrl+r")
            await app.workers.wait_for_complete()
            await pilot.pause()
            self.assertEqual(app.selected.id, "profile")
            await pilot.resize_terminal(80, 24)
            self.assertTrue(app.screen.has_class("narrow"))
            self.assertTrue(app.query_one("#refresh", Button).region.bottom <= 24)
            await pilot.press("q")

    async def test_failure_discards_old_results_and_can_retry(self):
        app = DoctorApp()
        async with app.run_test() as pilot:
            await app.workers.wait_for_complete()
            self.collect.side_effect = TimeoutError()
            await pilot.press("ctrl+r")
            await app.workers.wait_for_complete()
            self.assertIsNone(app.report)
            self.assertEqual(app.query_one(DataTable).row_count, 0)
            self.assertIn("неизвестен", str(app.query_one("#summary", Static).content))
            self.assertFalse(app.query_one("#refresh", Button).disabled)
            self.collect.side_effect = None
            await pilot.press("ctrl+r")
            await app.workers.wait_for_complete()
            self.assertIsNotNone(app.report)

    async def test_open_in_tmux_returns_exact_file_after_ui_exit(self):
        app = DoctorApp()
        with patch.dict(os.environ, TMUX="test-socket,0,0"):
            async with app.run_test() as pilot:
                await app.workers.wait_for_complete()
                await pilot.press("down", "ctrl+o")
            self.assertEqual(app.return_value, str(REPO / "profile/modules.conf"))


if __name__ == "__main__":
    unittest.main()
