from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "bin" / "codex-agents-local"


def load_module():
    loader = importlib.machinery.SourceFileLoader("codex_agents_local", str(MODULE_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise RuntimeError("failed to load module spec")
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


cal = load_module()


class CodexAgentsLocalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_workspace_internal_agents_symlink_is_allowed(self) -> None:
        repo = self.root / "repo"
        repo.mkdir()
        (repo / "CLAUDE.md").write_text("shared base\n", encoding="utf-8")
        (repo / "AGENTS.local.md").write_text("local\n", encoding="utf-8")
        (repo / "AGENTS.md").symlink_to("CLAUDE.md")

        _root, entries = cal.sync_tree(repo, str(repo), write=True)

        self.assertEqual(1, len(entries))
        self.assertFalse(entries[0].blocked)
        override = (repo / "AGENTS.override.md").read_text(encoding="utf-8")
        self.assertIn("shared base", override)
        self.assertIn("local", override)

    def test_workspace_external_local_symlink_is_blocked(self) -> None:
        repo = self.root / "repo"
        outside = self.root / "outside"
        repo.mkdir()
        outside.mkdir()
        (outside / "secret.txt").write_text("secret\n", encoding="utf-8")
        (repo / "AGENTS.local.md").symlink_to(outside / "secret.txt")

        _root, entries = cal.sync_tree(repo, str(repo), write=True)

        self.assertEqual(1, len(entries))
        self.assertTrue(entries[0].blocked)
        self.assertIn("not a regular file under", entries[0].warning)
        self.assertFalse((repo / "AGENTS.override.md").exists())

    def test_override_symlink_is_not_written(self) -> None:
        repo = self.root / "repo"
        outside = self.root / "outside"
        repo.mkdir()
        outside.mkdir()
        (repo / "AGENTS.local.md").write_text("local\n", encoding="utf-8")
        (repo / "AGENTS.override.md").symlink_to(outside / "written.txt")

        _root, entries = cal.sync_tree(repo, str(repo), write=True)

        self.assertEqual(1, len(entries))
        self.assertTrue(entries[0].blocked)
        self.assertIn("AGENTS.override.md is a symlink", entries[0].warning)
        self.assertFalse((outside / "written.txt").exists())

    def test_unmanaged_override_is_not_overwritten(self) -> None:
        repo = self.root / "repo"
        repo.mkdir()
        (repo / "AGENTS.local.md").write_text("local\n", encoding="utf-8")
        (repo / "AGENTS.override.md").write_text("manual\n", encoding="utf-8")

        _root, entries = cal.sync_tree(repo, str(repo), write=True)

        self.assertEqual(1, len(entries))
        self.assertTrue(entries[0].blocked)
        self.assertEqual("manual\n", (repo / "AGENTS.override.md").read_text(encoding="utf-8"))

    def test_deleted_local_removes_only_managed_overrides(self) -> None:
        for name in ("managed", "manual", "symlink", "broken-local", "invalid-local"):
            directory = self.root / name
            directory.mkdir()
            (directory / "AGENTS.local.md").write_text("obsolete rule\n", encoding="utf-8")
        cal.sync_tree(self.root, str(self.root), write=True)
        for directory in self.root.iterdir():
            (directory / "AGENTS.local.md").unlink()
        manual = self.root / "manual" / "AGENTS.override.md"
        manual.write_text("manual rule\n", encoding="utf-8")
        symlink = self.root / "symlink" / "AGENTS.override.md"
        symlink.unlink()
        symlink.symlink_to("../managed/AGENTS.override.md")
        (self.root / "broken-local" / "AGENTS.local.md").symlink_to("missing.md")
        (self.root / "invalid-local" / "AGENTS.local.md").mkdir()
        managed = self.root / "managed" / "AGENTS.override.md"

        _root, preview = cal.sync_tree(self.root, str(self.root), write=False)
        self.assertTrue(managed.exists())
        self.assertTrue(any(entry.removed and not entry.wrote for entry in preview))
        _root, entries = cal.sync_tree(self.root, str(self.root), write=True)

        self.assertFalse(managed.exists())
        self.assertEqual("manual rule\n", manual.read_text(encoding="utf-8"))
        self.assertTrue(symlink.is_symlink())
        self.assertTrue((self.root / "broken-local" / "AGENTS.override.md").exists())
        self.assertTrue((self.root / "invalid-local" / "AGENTS.override.md").exists())
        self.assertEqual(1, sum(entry.removed and entry.wrote for entry in entries))

    def test_other_sessions_receive_local_removal_once(self) -> None:
        local = self.root / "AGENTS.local.md"
        local.write_text("obsolete rule\n", encoding="utf-8")
        root, entries = cal.sync_tree(self.root, str(self.root), write=True)
        state = {"roots": {}, "sessions": {}}
        for session in ("first", "second"):
            cal.mark_session_synced(state, session, root, entries)
        local.unlink()
        root, entries = cal.sync_tree(root, str(root), write=True)
        changed = cal.changed_entries_for_session(state, "first", root, entries)
        self.assertEqual(1, len(changed))
        self.assertIn("Discard earlier local instructions", cal.build_additional_context(root, changed))
        cal.mark_session_synced(state, "first", root, entries)
        root, entries = cal.sync_tree(root, str(root), write=True)
        self.assertEqual([], cal.changed_entries_for_session(state, "first", root, entries))
        changed = cal.changed_entries_for_session(state, "second", root, entries)
        self.assertEqual(1, len(changed))
        self.assertTrue(changed[0].removed)
        cal.mark_session_synced(state, "second", root, entries)
        self.assertEqual([], cal.changed_entries_for_session(state, "second", root, entries))

    def test_install_hooks_recovers_invalid_json_with_backup(self) -> None:
        codex_home = self.root / "codex-home"
        hooks_file = codex_home / "hooks.json"
        hooks_file.parent.mkdir(parents=True)
        hooks_file.write_text("{bad json", encoding="utf-8")
        old_home = os.environ.get("CODEX_HOME")
        os.environ["CODEX_HOME"] = str(codex_home)
        self.addCleanup(self._restore_env, "CODEX_HOME", old_home)

        cal.install_hooks("/tmp/codex-agents-local", include_session_start=True, include_pre_tool_use=False)

        self.assertTrue(hooks_file.with_suffix(".json.bak").exists())
        hooks = json.loads(hooks_file.read_text(encoding="utf-8"))["hooks"]
        self.assertIn("SessionStart", hooks)
        self.assertIn("UserPromptSubmit", hooks)
        self.assertNotIn("PreToolUse", hooks)

    def test_prune_state_drops_old_and_caps_sessions(self) -> None:
        state = {
            "sessions": {
                "old": {"roots": {"r": {"updated_at": 100}}},
                "newest": {"roots": {"r": {"updated_at": 990}}},
                "middle": {"roots": {"r": {"updated_at": 980}}},
                "extra": {"roots": {"r": {"updated_at": 970}}},
            }
        }

        cal.prune_state(state, now=1000, max_age_seconds=100, max_sessions=2)

        self.assertEqual(["newest", "middle"], list(state["sessions"].keys()))

    @staticmethod
    def _restore_env(name: str, value: str | None) -> None:
        if value is None:
            os.environ.pop(name, None)
        else:
            os.environ[name] = value


if __name__ == "__main__":
    unittest.main()
