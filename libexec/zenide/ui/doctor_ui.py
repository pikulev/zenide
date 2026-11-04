"""Интерактивная витрина doctor. Изменения конфигов остаются в редакторе."""

from __future__ import annotations

import asyncio
import os
from pathlib import Path
import shutil
import subprocess

from rich.text import Text
from textual import events, on, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, VerticalScroll
from textual.widgets import Button, Checkbox, DataTable, Footer, Input, Static
from textual.worker import get_current_worker

from model import Check, Report, collect, dispatcher, visible_checks


class DoctorApp(App[str | None]):
    TITLE = "zenide doctor"
    ENABLE_COMMAND_PALETTE = False
    BINDINGS = [
        Binding("ctrl+r", "refresh_checks", "Проверить"),
        Binding("ctrl+p", "toggle_problems", "Проблемы"),
        Binding("ctrl+o", "open_file", "Файл"),
        Binding("slash", "search", "Поиск"),
        Binding("escape", "focus_checks", show=False),
        Binding("q", "quit", "Выход"),
    ]

    def __init__(self, *, command: list[str] | None = None, css_path: Path | None = None):
        root = Path(os.environ["ZENIDE_ROOT"])
        profile = Path(os.environ["ZENIDE_PROFILE"])
        if css_path is None:
            custom = profile / "doctor.tcss.local"
            css_path = custom if custom.is_file() else root / "profile/doctor.tcss.local.example"
        super().__init__(css_path=css_path)
        self.command = command or [str(dispatcher()), "doctor", "--json"]
        self.report: Report | None = None
        self.selected: Check | None = None
        self.busy = False
        self.by_id: dict[str, Check] = {}

    def compose(self) -> ComposeResult:
        yield Static("zenide doctor", id="heading", markup=False)
        yield Static("Проверки ещё не выполнялись", id="summary", markup=False)
        with Horizontal(id="filters"):
            yield Input(placeholder="Найти проверку, клавишу или путь…", id="search")
            yield Checkbox("Только проблемы", id="problems")
        with Horizontal(id="body"):
            yield DataTable(id="checks", cursor_type="row", show_row_labels=False)
            with VerticalScroll(id="details"):
                yield Static("Подробности", id="detail-title", markup=False)
                yield Static("", id="detail", markup=False)
                yield Static("", id="hint", markup=False)
                yield Static("", id="file", markup=False)
        with Horizontal(id="actions"):
            yield Button("Проверить снова", id="refresh")
            yield Button("Открыть файл", id="open", disabled=True)
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one(DataTable)
        table.add_columns("Статус", "Проверка")
        table.focus()
        self.screen.set_class(self.size.width < 100, "narrow")
        self.action_refresh_checks()

    def on_resize(self, event: events.Resize) -> None:
        self.screen.set_class(event.size.width < 100, "narrow")

    @work(exclusive=True, group="doctor")
    async def action_refresh_checks(self) -> None:
        self.busy = True
        self.query_one("#refresh", Button).disabled = True
        self.query_one("#open", Button).disabled = True
        self.query_one("#summary", Static).update("Проверяю… Таймаут: 30 секунд.")
        try:
            report = await collect(self.command)
        except asyncio.CancelledError:
            raise
        except (OSError, ValueError, TimeoutError) as exc:
            message = "Проверки не завершились за 30 секунд." if isinstance(exc, TimeoutError) else str(exc)
            self.report = None
            self.by_id = {}
            self.query_one(DataTable).clear()
            self.show_check(None)
            self.query_one("#summary", Static).update("Проверка не завершена — результат неизвестен")
            self.query_one("#detail", Static).update(message)
            self.query_one("#hint", Static).update(
                "Запусти zenide doctor в терминале для подробностей. Ctrl-r — повторить."
            )
        else:
            self.report = report
            self.query_one("#heading", Static).update(f"zenide doctor  ·  Профиль: {report.profile}")
            self.rebuild()
        finally:
            if not get_current_worker().is_cancelled:
                self.busy = False
                self.query_one("#refresh", Button).disabled = False
                self.query_one("#open", Button).disabled = not self.can_open()

    def rebuild(self) -> None:
        if self.report is None:
            return
        query = self.query_one(Input).value
        problems = self.query_one(Checkbox).value
        checks = visible_checks(self.report, query, problems)
        old_id = self.selected.id if self.selected else None
        self.by_id = {check.id: check for check in checks}
        table = self.query_one(DataTable)
        table.clear()
        marks = {"ok": "ok", "warn": "~", "error": "нет", "info": "·"}
        for check in checks:
            table.add_row(Text(marks[check.status]), Text(check.title), key=check.id)
        index = next((i for i, check in enumerate(checks) if check.id == old_id), 0)
        if checks:
            table.move_cursor(row=index)
            self.show_check(checks[index])
        else:
            self.show_check(None)
        errors = sum(check.status == "error" for check in self.report.checks)
        warnings = sum(check.status == "warn" for check in self.report.checks)
        self.query_one("#summary", Static).update(
            f"Ошибки: {errors}  ·  Предупреждения: {warnings}  ·  "
            f"Показано: {len(checks)}/{len(self.report.checks)}"
        )

    def can_open(self) -> bool:
        return bool(self.selected and self.selected.file and Path(self.selected.file).is_file())

    def show_check(self, check: Check | None) -> None:
        self.selected = check
        title = self.query_one("#detail-title", Static)
        for status in ("error", "warn", "ok", "info"):
            title.set_class(check is not None and check.status == status, status)
        self.query_one("#detail-title", Static).update(
            f"{check.group_title} / {check.title}" if check else "Нет выбранной проверки"
        )
        self.query_one("#detail", Static).update(check.detail if check else "По этому фильтру проверок нет.")
        self.query_one("#hint", Static).update(
            f"Что можно сделать\n{check.hint}" if check and check.hint else ""
        )
        self.query_one("#file", Static).update(f"Файл\n{check.file}" if check and check.file else "")
        self.query_one("#open", Button).disabled = self.busy or not self.can_open()

    @on(DataTable.RowHighlighted)
    def row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        # После смены фильтра в очереди ещё могут быть события удалённых строк.
        check = self.by_id.get(str(event.row_key.value))
        if check:
            self.show_check(check)

    @on(Input.Changed)
    @on(Checkbox.Changed)
    def filters_changed(self) -> None:
        self.rebuild()

    @on(Input.Submitted)
    def search_submitted(self) -> None:
        self.action_focus_checks()

    @on(Button.Pressed, "#refresh")
    def refresh_pressed(self) -> None:
        self.action_refresh_checks()

    @on(Button.Pressed, "#open")
    def open_pressed(self) -> None:
        self.action_open_file()

    def action_toggle_problems(self) -> None:
        self.query_one(Checkbox).toggle()

    def action_search(self) -> None:
        self.query_one(Input).focus()

    def action_focus_checks(self) -> None:
        self.query_one(DataTable).focus()

    def action_open_file(self) -> None:
        if self.busy or not self.can_open() or self.selected is None:
            return
        path = self.selected.file
        if os.environ.get("TMUX"):
            # Сначала закрываем TUI, затем мост переключает окно редактора.
            self.exit(path)
        elif os.environ.get("ZENIDE_EDITOR") == "helix" and shutil.which("hx"):
            with self.suspend():
                subprocess.run(["hx", "--", path], check=False)
            self.action_refresh_checks()
        else:
            self.notify(f"Открой файл своим редактором: {path}", markup=False)


def main() -> None:
    path = DoctorApp().run()
    if path:
        executable = str(dispatcher())
        os.execv(executable, [executable, "open", path])


if __name__ == "__main__":
    main()
