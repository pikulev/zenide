"""Контракт doctor: один набор проверок, корректный JSON и изолированный профиль."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class DoctorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="zenide-doctor-")
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.root = base / "clone"
        self.home = base / "home"
        self.profile = base / 'профиль "[red]" \\ с\tтабом\nи строкой'
        self.profile.mkdir()
        self.config = self.home / ".config"
        self.config.mkdir(parents=True)
        for name in ("bin/zenide", "libexec/zenide/doctor", "libexec/zenide/lib/profile.sh",
                     "libexec/zenide/lib/doctor-report.sh", "libexec/zenide/ui/launch.sh"):
            dst = self.root / name
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO / name, dst)
        (self.root / "libexec/zenide/editor/helix").mkdir(parents=True)
        (self.root / "ide").mkdir()
        (self.root / "ide/LAYERS").write_text("tmux | core | | шина\nhelix | contract | CONTRACT.toml | reload\n")
        (self.root / "VERSION").write_text("test")
        (self.profile / ".zenide-version").write_text("test")
        (self.profile / "modules.conf").write_text('modules="fixture fixture absent"\n')
        module = self.root / "modules/fixture"
        module.mkdir(parents=True)
        self.executable(module / "init.sh", "# Модуль для теста\nexit 0\n")
        self.executable(module / "check.sh", "printf 'модуль [red] \\\"quote\\\" \\\\ slash\\nsecond\\tline\\033!\\001'\n")
        (self.config / "zenide").symlink_to(self.root, target_is_directory=True)
        (self.config / "zenide-profile").symlink_to(self.profile, target_is_directory=True)
        (self.config / "tmux").mkdir()
        (self.config / "tmux/tmux.conf").write_text("")
        (self.config / "helix").mkdir()
        (self.config / "helix/config.toml").write_text("[editor.auto-save]\nfocus-lost = true\n")
        self.tools = base / "tools"
        self.tools.mkdir()
        for tool in ("git", "fzf", "hx", "yazi", "lazygit", "fd", "rg", "bat", "delta", "scooter", "zoxide", "zenide"):
            self.executable(self.tools / tool, "exit 0\n")
        self.executable(self.tools / "tmux", "echo 'tmux 3.6a'\n")
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith(("ZENIDE_", "XDG_", "MISE_")) or key in ("TMUX", "TMUX_PANE"):
                del self.env[key]
        self.env.update(HOME=str(self.home), ZENIDE_PROFILE=str(self.profile),
                        PATH=f"{self.tools}:/usr/bin:/bin")

    @staticmethod
    def executable(path, source):
        path.write_text("#!/bin/sh\n" + source)
        path.chmod(0o755)

    def run_doctor(self, *args):
        return subprocess.run([str(self.root / "bin/zenide"), "doctor", *args],
                              env=self.env, capture_output=True, timeout=10)

    def report(self):
        result = self.run_doctor("--json")
        self.assertEqual(result.stderr, b"")
        report = json.loads(result.stdout)
        self.assertEqual(report["exit_code"], result.returncode)
        return report

    def test_json_roundtrip_and_text_share_checks(self):
        report = self.report()
        self.assertEqual(report["schema_version"], 1)
        self.assertEqual(report["profile"], str(self.profile))
        self.assertEqual(report["exit_code"], 0)
        ids = [row["id"] for row in report["checks"]]
        self.assertEqual(len(ids), len(set(ids)))
        text = self.run_doctor().stdout.decode()
        for row in report["checks"]:
            self.assertIn(row["title"], text)
            self.assertIn(row["detail"], text)
        check = next(row for row in report["checks"] if row["id"] == "module.fixture.check")
        self.assertIn("\nsecond\tline\x1b!\x01", check["detail"])
        self.assertIn("[red]", check["detail"])
        self.assertNotIn("mise.binary", ids)

    def test_failure_keeps_valid_report_and_stable_id(self):
        before = {row["id"] for row in self.report()["checks"]}
        (self.tools / "hx").unlink()
        (self.config / "helix/config.toml").write_text("[editor.auto-save]\nfocus-lost = false\n")
        report = self.report()
        self.assertEqual(report["exit_code"], 1)
        self.assertEqual(before, {row["id"] for row in report["checks"]})
        self.assertEqual({row["id"] for row in report["checks"] if row["status"] == "error"},
                         {"required.editor", "helix.autosave"})

    def test_shadow_and_failed_probe_do_not_claim_success(self):
        (self.home / ".gitconfig").write_text("[user]\nname = test\n")
        (self.home / ".tmux.conf").write_text("source-file ~/.config/tmux/tmux.conf\n")
        self.executable(self.tools / "mise", "exit 2\n")
        checks = {row["id"]: row for row in self.report()["checks"]}
        for key in ("shadow.git", "shadow.tmux", "mise.missing", "module.absent.init"):
            self.assertEqual(checks[key]["status"], "warn")

    def test_modes_and_missing_optional_environment(self):
        for args in (("--wat",), ("--json", "--ui"), ("--ui", "--json")):
            self.assertEqual(self.run_doctor(*args).returncode, 2)
        result = self.run_doctor("--ui")
        self.assertEqual(result.returncode, 2)
        self.assertIn("uv sync --locked", result.stdout.decode())
        self.assertFalse((self.home / ".local/share/zenide").exists())


if __name__ == "__main__":
    unittest.main()
