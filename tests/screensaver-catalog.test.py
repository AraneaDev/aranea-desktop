"""Exercise the real catalog, atomic preference files, and owner CLI boundary."""

import concurrent.futures
import copy
import importlib
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert (REPO / "tools/screensaver/catalog.py").is_file(), (
            "scene catalog implementation is missing"
        )
        cls.catalog_api = importlib.import_module("tools.screensaver.catalog")
        cls.preferences = importlib.import_module("tools.screensaver.preferences")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.repo = self.base / "repo"
        self.catalog_file = self.repo / "branding/screensavers/catalog.json"
        self.catalog_file.parent.mkdir(parents=True)
        self.source = json.loads(
            (REPO / "branding/screensavers/catalog.json").read_text()
        )
        self.catalog_file.write_text(json.dumps(self.source))
        for name in (
            "live/index.html",
            "live/preview.png",
            "aranea-spider.glb",
            "silk-chamber.mp4",
            "silk-chamber.png",
        ):
            asset = self.repo / "branding/3d" / name
            asset.parent.mkdir(parents=True, exist_ok=True)
            asset.write_bytes(b"fixture")
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for name in ("chromium", "mpv"):
            executable = self.bin / name
            executable.write_text("#!/bin/sh\nexit 99\n")
            executable.chmod(0o755)
        self.old_path = os.environ.get("PATH", "")
        os.environ["PATH"] = str(self.bin)
        self.addCleanup(os.environ.__setitem__, "PATH", self.old_path)
        self.config = self.base / "config"
        self.packaged = self.base / "omarchy"
        self.idle_service = self.packaged / "shell/plugins/services/idle/Service.qml"
        self.idle_service.parent.mkdir(parents=True)
        # Status probes only this file's presence; it never loads QML.
        self.idle_service.write_text("// Test host presence fixture.\n")
        self.enterContext(patch.dict(os.environ, OMARCHY_PATH=str(self.packaged)))

    def load(self):
        return self.catalog_api.load_catalog(self.repo)

    def test_default_read_and_status_create_nothing(self):
        self.assertEqual(
            self.preferences.read_preferences(self.config),
            {"version": 1, "selectedId": "silk-journey", "mode": "single"},
        )
        self.assertFalse(self.config.exists())
        snapshot = self.cli("status", "--json")
        self.assertEqual(snapshot.returncode, 0, snapshot.stderr)
        state = json.loads(snapshot.stdout)
        self.assertEqual(state["selectedId"], "silk-journey")
        self.assertEqual(state["mode"], "single")
        self.assertEqual(
            state["session"],
            {"running": False, "ready": False, "sceneId": None, "preview": False},
        )
        self.assertEqual(state["integration"], {"installed": False, "reachable": False})
        self.assertEqual(
            state["idle"],
            {
                "screensaverSeconds": 150,
                "lockSeconds": 300,
                "stayAwake": False,
                "screensaverOff": False,
                "error": None,
            },
        )
        self.assertFalse(self.config.exists())

    def test_absent_host_keeps_pause_indicators_unknown_without_creating_state(self):
        self.idle_service.unlink()
        snapshot = self.cli("status", "--json")
        self.assertEqual(snapshot.returncode, 0, snapshot.stderr)
        state = json.loads(snapshot.stdout)
        self.assertEqual(
            state["idle"],
            {
                "screensaverSeconds": 150,
                "lockSeconds": 300,
                "stayAwake": None,
                "screensaverOff": None,
                "error": None,
            },
        )
        self.assertEqual(state["availability"], "available")
        self.assertFalse(self.config.exists())
        self.assertFalse((self.base / "state").exists())
        self.assertFalse((self.base / "home").exists())

    def test_three_entries_and_projection(self):
        scenes = self.load()
        self.assertEqual(
            [s.id for s in scenes], ["silk-journey", "silk-chamber", "omarchy"]
        )
        self.assertEqual([s.renderer for s in scenes], ["web", "video", "stock"])
        self.assertTrue(all(s.available for s in scenes))
        item = scenes[0].projection()
        self.assertEqual(
            set(item),
            {
                "id",
                "label",
                "description",
                "renderer",
                "thumbnail",
                "available",
                "reason",
                "shuffleEligible",
            },
        )
        self.assertEqual(
            item["thumbnail"], str(self.repo / "branding/3d/live/preview.png")
        )
        self.assertIsNone(scenes[2].thumbnail)
        self.assertFalse(scenes[2].shuffle_eligible)
        # The shipped catalog must also parse against its real authored assets.
        self.assertTrue(all(s.available for s in self.catalog_api.load_catalog(REPO)))

    def test_missing_dependencies_disable_only_affected_scene(self):
        for executable, index in (("chromium", 0), ("mpv", 1)):
            with self.subTest(executable=executable):
                (self.bin / executable).rename(self.bin / "removed")
                scenes = self.load()
                self.assertFalse(scenes[index].available)
                self.assertIn(executable, scenes[index].reason)
                self.assertTrue(
                    all(s.available for i, s in enumerate(scenes) if i != index)
                )
                (self.bin / "removed").rename(self.bin / executable)

    def test_missing_asset_disables_only_affected_scene(self):
        (self.repo / "branding/3d/silk-chamber.mp4").unlink()
        scenes = self.load()
        self.assertTrue(scenes[0].available)
        self.assertFalse(scenes[1].available)
        self.assertIn("silk-chamber.mp4", scenes[1].reason)
        self.assertTrue(scenes[2].available)

    def test_missing_web_directory_disables_only_web_scene(self):
        shutil.rmtree(self.repo / "branding/3d/live")
        scenes = self.load()
        self.assertFalse(scenes[0].available)
        self.assertTrue(scenes[1].available)
        self.assertTrue(scenes[2].available)

    def test_rejects_invalid_catalog_fields(self):
        cases = [
            ("version", 2),
            ("version", True),
            ("id", "../escape"),
            ("id", "x" * 65),
            ("renderer", "shell"),
            ("entry", "branding/../outside.html"),
            ("entry", "/tmp/outside.html"),
            ("entry", "."),
            ("entry", "tools/outside.html"),
            ("label", "<b>Silk</b>"),
            ("description", "x" * 513),
            ("command", "touch /tmp/forbidden"),
        ]
        for field, value in cases:
            with self.subTest(field=field, value=value):
                source = copy.deepcopy(self.source)
                target = source if field == "version" else source["scenes"][0]
                target[field] = value
                self.catalog_file.write_text(json.dumps(source))
                with self.assertRaises(ValueError):
                    self.load()

    def test_rejects_duplicate_ids_and_symlink_escape(self):
        source = copy.deepcopy(self.source)
        source["scenes"][1]["id"] = "silk-journey"
        self.catalog_file.write_text(json.dumps(source))
        with self.assertRaises(ValueError):
            self.load()
        self.catalog_file.write_text(json.dumps(self.source))
        asset = self.repo / "branding/3d/aranea-spider.glb"
        asset.unlink()
        asset.symlink_to(self.base / "outside")
        with self.assertRaises(ValueError):
            self.load()
        asset.unlink()
        asset.write_bytes(b"fixture")
        nested = self.repo / "branding/3d/live/nested"
        nested.symlink_to(self.base)
        with self.assertRaises(ValueError):
            self.load()

    def test_malformed_preferences_retained_and_invalid_mutations_do_not_write(self):
        path = self.config / "aranea/screensaver.json"
        path.parent.mkdir(parents=True)
        for content in (
            b"{broken",
            b'{"version":2,"selectedId":"silk-journey","mode":"single"}',
            b'{"version":true,"selectedId":"silk-journey","mode":"single"}',
            b'{"version":1,"selectedId":"../escape","mode":"single"}',
        ):
            path.write_bytes(content)
            with self.assertRaises(ValueError):
                self.preferences.read_preferences(self.config)
            with self.assertRaises(ValueError):
                self.preferences.configure_preferences(
                    self.config, "silk-journey", "single", self.load()
                )
            self.assertEqual(path.read_bytes(), content)
        path.unlink()
        prefs = self.preferences.configure_preferences(
            self.config, "silk-chamber", "single", self.load()
        )
        self.assertEqual(
            prefs, {"version": 1, "selectedId": "silk-chamber", "mode": "single"}
        )
        before = path.read_bytes()
        for scene_id, mode in (
            ("../evil", "single"),
            ("unknown", "single"),
            ("silk-chamber", "playlist"),
        ):
            with self.assertRaises(ValueError):
                self.preferences.configure_preferences(
                    self.config, scene_id, mode, self.load()
                )
            self.assertEqual(path.read_bytes(), before)
        (self.bin / "mpv").unlink()
        with self.assertRaises(ValueError):
            self.preferences.configure_preferences(
                self.config, "silk-chamber", "single", self.load()
            )
        self.assertEqual(path.read_bytes(), before)
        # Shuffle remembers a known unavailable selection but needs a valid pool.
        self.preferences.configure_preferences(
            self.config, "silk-chamber", "shuffle", self.load()
        )
        (self.bin / "chromium").unlink()
        with self.assertRaises(ValueError):
            self.preferences.configure_preferences(
                self.config, "omarchy", "shuffle", self.load()
            )

    def test_concurrent_configure_produces_complete_value(self):
        # Separate processes contend on the stable adjacent lock, including first creation.
        commands = [
            ("silk-journey", "single"),
            ("silk-chamber", "shuffle"),
            ("omarchy", "single"),
        ] * 8
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(
                pool.map(lambda args: self.cli("configure", *args, "--json"), commands)
            )
        self.assertTrue(
            all(result.returncode == 0 for result in results),
            [r.stderr for r in results],
        )
        prefs = self.preferences.read_preferences(self.config)
        self.assertIn((prefs["selectedId"], prefs["mode"]), commands)
        self.assertEqual(set(prefs), {"version", "selectedId", "mode"})
        self.assertEqual(list((self.config / "aranea").glob("*.tmp")), [])

    def test_shuffle_excludes_stock_avoids_last_and_handles_empty_pool(self):
        scenes = self.load()
        rng = random.Random(7)
        choose = self.catalog_api.choose_scene
        prefs = {"selectedId": "silk-journey", "mode": "shuffle"}
        self.assertEqual(choose(scenes, prefs, "silk-journey", rng).id, "silk-chamber")
        self.assertEqual(choose(scenes, prefs, "silk-chamber", rng).id, "silk-journey")
        for _ in range(20):
            self.assertNotEqual(choose(scenes, prefs, None, rng).id, "omarchy")
        (self.bin / "mpv").unlink()
        self.assertEqual(
            choose(self.load(), prefs, "silk-journey", rng).id, "silk-journey"
        )
        (self.bin / "chromium").unlink()
        with self.assertRaises(ValueError):
            choose(self.load(), prefs, None, rng)
        self.assertEqual(
            choose(
                self.load(), {"selectedId": "omarchy", "mode": "single"}, None, rng
            ).id,
            "omarchy",
        )

    def test_last_scene_uses_state_home_and_atomic_readback(self):
        state_home = self.base / "state"
        self.assertIsNone(self.preferences.read_last_scene(state_home))
        self.assertFalse(state_home.exists())
        self.preferences.write_last_scene(state_home, "silk-chamber")
        self.assertEqual(self.preferences.read_last_scene(state_home), "silk-chamber")
        with self.assertRaises(ValueError):
            self.preferences.write_last_scene(state_home, "../escape")
        self.assertEqual(self.preferences.read_last_scene(state_home), "silk-chamber")
        self.assertFalse(self.config.exists())

    def test_implicit_xdg_and_aranea_state_locations(self):
        overrides = {
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_STATE_HOME": str(self.base / "xdg-state"),
            "ARANEA_STATE_ROOT": str(self.base / "aranea-state"),
        }
        previous = {key: os.environ.get(key) for key in overrides}
        os.environ.update(overrides)
        try:
            self.assertEqual(
                self.preferences.read_preferences()["selectedId"], "silk-journey"
            )
            self.assertFalse(self.config.exists())
            self.preferences.write_last_scene(None, "silk-journey")
            self.assertEqual(self.preferences.read_last_scene(), "silk-journey")
            self.assertTrue(
                (self.base / "aranea-state/screensaver-last.json").is_file()
            )
            self.assertFalse((self.base / "xdg-state").exists())
            self.preferences.write_last_scene(self.base / "explicit", "silk-chamber")
            self.assertTrue(
                (self.base / "explicit/aranea/screensaver-last.json").is_file()
            )
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

    def cli(self, *args):
        env = dict(
            os.environ,
            HOME=str(self.base / "home"),
            XDG_CONFIG_HOME=str(self.config),
            XDG_STATE_HOME=str(self.base / "state"),
            XDG_RUNTIME_DIR=str(self.base / "runtime"),
        )
        env["PATH"] = str(self.bin) + os.pathsep + self.old_path
        return subprocess.run(
            ["bash", str(REPO / "scripts/aranea-screensaver"), *args],
            check=False,
            env=env,
            text=True,
            capture_output=True,
            timeout=10,
        )

    def test_cli_reads_timing_and_never_executes_config_text(self):
        shell = self.config / "omarchy/shell.json"
        shell.parent.mkdir(parents=True)
        shell.write_text('{"idle":{"screensaver":900,"lock":1200}}')
        response = self.cli("list", "--json")
        self.assertEqual(response.returncode, 0, response.stderr)
        self.assertEqual(
            json.loads(response.stdout)["idle"],
            {
                "screensaverSeconds": 900,
                "lockSeconds": 1200,
                "stayAwake": False,
                "screensaverOff": False,
                "error": None,
            },
        )
        bad = self.cli(
            "configure", "$(touch /tmp/aranea-should-not-exist)", "single", "--json"
        )
        self.assertNotEqual(bad.returncode, 0)
        self.assertIsInstance(json.loads(bad.stdout)["error"], str)
        self.assertTrue(bad.stderr)
        self.assertFalse((self.config / "aranea").exists())
        shell.write_text('{"idle":{"screensaver":0}}')
        self.assertEqual(
            json.loads(self.cli("status", "--json").stdout)["idle"],
            {
                "screensaverSeconds": 0,
                "lockSeconds": 300,
                "stayAwake": False,
                "screensaverOff": False,
                "error": None,
            },
        )
        shell.write_text('{"idle":{"screensaver":"900","lock":true}}')
        self.assertEqual(
            json.loads(self.cli("status", "--json").stdout)["idle"],
            {
                "screensaverSeconds": None,
                "lockSeconds": None,
                "stayAwake": False,
                "screensaverOff": False,
                "error": "Omarchy idle deadlines must be integer seconds from 0 to 86400",
            },
        )

    def test_cli_reports_invalid_config_and_unknown_remembered_id(self):
        path = self.config / "aranea/screensaver.json"
        path.parent.mkdir(parents=True)
        for content in ("{bad", '{"version":1,"selectedId":"unknown","mode":"single"}'):
            path.write_text(content)
            result = self.cli("status", "--json")
            self.assertNotEqual(result.returncode, 0)
            state = json.loads(result.stdout)
            self.assertEqual(state["availability"], "unavailable")
            self.assertTrue(state["catalogAvailable"])
            self.assertEqual(len(state["choices"]), 3)
            self.assertTrue(state["error"])
            self.assertEqual(path.read_text(), content)


if __name__ == "__main__":
    unittest.main(verbosity=2)
