"""Timing persistence stays independent from preferences and partial Settings reads."""

import concurrent.futures
import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


class TimingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = self.root / "config"
        self.config.mkdir()
        self.shell = self.config / "omarchy/shell.json"
        self.shell.parent.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        reload = self.bin / "omarchy-shell"
        reload.write_text(
            '#!/bin/sh\nprintf "%s\\n" "$*" >> "$RELOAD_LOG"\n[ "$*" = "shell reloadConfig" ] || exit 91\nexit "${RELOAD_RC:-0}"\n'
        )
        reload.chmod(0o755)
        self.packaged = self.root / "omarchy"
        (self.packaged / "config/omarchy").mkdir(parents=True)
        (self.packaged / "config/omarchy/shell.json").write_text(
            '{"version":1,"bar":{"test":true},"idle":{"screensaver":150,"lock":300}}'
        )
        self.env = dict(
            os.environ,
            XDG_CONFIG_HOME=str(self.config),
            OMARCHY_PATH=str(self.packaged),
            RELOAD_LOG=str(self.root / "reload.log"),
            PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
        )

    def owner(self, *args, **env):
        return subprocess.run(
            [str(REPO / "scripts/aranea-screensaver"), *args, "--json"],
            env=dict(self.env, **env),
            capture_output=True,
            text=True,
            check=False,
        )

    def save(self, saver="900", lock="1200", **env):
        return self.owner("configure-idle", saver, lock, **env)

    def test_save_preserves_other_fields_and_subminute_values(self):
        before = {
            "bar": {"layout": ["mine"]},
            "plugins": ["custom"],
            "idle": {"screensaver": 900, "lock": 1200, "dpms": 42},
        }
        self.shell.write_text(json.dumps(before))
        result = self.save("31", "89")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(result.stdout)
        self.assertEqual(state["idle"]["screensaverSeconds"], 31)
        self.assertEqual(
            state["timingUpdate"], {"persisted": True, "applied": True, "error": None}
        )
        before["idle"].update(screensaver=31, lock=89)
        self.assertEqual(json.loads(self.shell.read_text()), before)
        self.assertEqual((self.root / "reload.log").read_text(), "shell reloadConfig\n")

    def test_invalid_requests_leave_bytes_unchanged(self):
        self.shell.write_text('{"idle":{"screensaver":900,"lock":1200}}\n')
        before = self.shell.read_bytes()
        for saver, lock in (
            ("-1", "1200"),
            ("1.0", "1200"),
            ("+1", "1200"),
            ("true", "1200"),
            ("86401", "0"),
            ("900", "900"),
            ("901", "900"),
            ("1;touch pwn", "9"),
        ):
            with self.subTest(saver=saver, lock=lock):
                result = self.save(saver, lock)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.shell.read_bytes(), before)
        self.assertFalse((self.root / "reload.log").exists())

    def test_disabled_values_and_maximum(self):
        for saver, lock in (("0", "0"), ("0", "1"), ("86400", "0"), ("1", "86400")):
            result = self.save(saver, lock)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                json.loads(self.shell.read_text())["idle"],
                {"screensaver": int(saver), "lock": int(lock)},
            )

    def test_malformed_existing_config_is_not_normalized(self):
        for value in ("bad", "[]", '{"idle":false}', '{"idle":null}'):
            self.shell.write_text(value)
            result = self.save()
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.shell.read_text(), value)

    def test_missing_save_uses_packaged_defaults_and_missing_defaults_fails(self):
        result = self.save()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(self.shell.read_text())["bar"]["test"])
        self.shell.unlink()
        result = self.save(OMARCHY_PATH=str(self.root / "absent"))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.shell.exists())

    def test_symlink_target_and_mode_survive_concurrent_atomic_saves(self):
        target = self.root / "dotfiles.json"
        target.write_text('{"idle":{"extra":7},"bar":{"mine":true}}')
        target.chmod(0o640)
        self.shell.symlink_to(target)
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
            results = list(
                executor.map(lambda i: self.save(str(20 + i), str(100 + i)), range(12))
            )
        self.assertTrue(
            all(r.returncode == 0 for r in results), [r.stderr for r in results]
        )
        self.assertTrue(self.shell.is_symlink())
        data = json.loads(target.read_text())
        self.assertEqual(data["idle"]["extra"], 7)
        self.assertEqual(data["idle"]["lock"] - data["idle"]["screensaver"], 80)
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)
        self.assertFalse(list(self.root.glob(".shell.json.aranea.*")))

    def test_saved_but_not_applied_has_authoritative_readback(self):
        result = self.save("600", "1800", RELOAD_RC="8")
        self.assertNotEqual(result.returncode, 0)
        state = json.loads(result.stdout)
        self.assertEqual(state["idle"]["screensaverSeconds"], 600)
        self.assertTrue(state["timingUpdate"]["persisted"])
        self.assertFalse(state["timingUpdate"]["applied"])
        self.assertIn("saved", state["error"].lower())

    def test_real_settings_reports_saved_reload_failure_and_independent_success(self):
        command = [
            str(REPO / "scripts/aranea-settings"),
            "configure",
            "screensaver-timing",
            "0",
            "89",
            "--json",
        ]
        result = subprocess.run(
            command,
            env=dict(self.env, RELOAD_RC="8"),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["schemaVersion"], 1)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "HELPER_FAILED")
        self.assertIn("saved but not applied", data["error"]["message"])
        self.assertTrue(data["result"]["screensaverTiming"]["persisted"])
        self.assertFalse(data["result"]["screensaverTiming"]["applied"])
        self.assertEqual(data["state"]["screensaver"]["idle"]["screensaverSeconds"], 0)
        self.assertEqual(data["state"]["screensaver"]["idle"]["lockSeconds"], 89)
        prefs = self.config / "aranea/screensaver.json"
        prefs.parent.mkdir(exist_ok=True)
        prefs.write_text("invalid")
        result = subprocess.run(
            command, env=self.env, capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertTrue(data["result"]["screensaverTiming"]["applied"])
        self.assertEqual(data["state"]["screensaver"]["idle"]["lockSeconds"], 89)
        self.assertEqual(prefs.read_text(), "invalid")

    def test_reload_is_bounded_after_persistence(self):
        helper = self.bin / "omarchy-shell"
        helper.write_text("#!/usr/bin/python3\nimport time\ntime.sleep(8)\n")
        began = time.monotonic()
        result = self.save()
        self.assertLess(time.monotonic() - began, 4)
        self.assertNotEqual(result.returncode, 0)
        state = json.loads(result.stdout)
        self.assertTrue(state["timingUpdate"]["persisted"])
        self.assertFalse(state["timingUpdate"]["applied"])
        self.assertEqual(state["idle"]["lockSeconds"], 1200)

    def test_host_pause_indicators_are_observed_without_mutation(self):
        service = self.packaged / "shell/plugins/services/idle/Service.qml"
        service.parent.mkdir(parents=True)
        service.write_text("pinned host fixture")
        home = self.root / "home"
        marker = home / ".local/state/omarchy/indicators/stay-awake"
        marker.parent.mkdir(parents=True)
        marker.touch()
        off = home / ".local/state/omarchy/toggles/screensaver-off"
        off.parent.mkdir(parents=True)
        off.touch()
        state = json.loads(self.owner("status", HOME=str(home)).stdout)
        self.assertTrue(state["idle"]["stayAwake"])
        self.assertTrue(state["idle"]["screensaverOff"])
        self.assertFalse(self.shell.exists())
        self.assertTrue(marker.exists())
        self.assertTrue(off.exists())
        service.unlink()
        state = json.loads(self.owner("status", HOME=str(home)).stdout)
        self.assertIsNone(state["idle"]["stayAwake"])
        self.assertIsNone(state["idle"]["screensaverOff"])

    def test_corrupt_scene_preferences_do_not_block_timing_save(self):
        prefs = self.config / "aranea/screensaver.json"
        prefs.parent.mkdir()
        prefs.write_text("invalid")
        result = self.save()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(prefs.read_text(), "invalid")
        self.assertTrue(json.loads(result.stdout)["timingUpdate"]["applied"])

    def test_status_is_read_only_and_reports_host_flags(self):
        result = self.owner("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.shell.exists())
        idle = json.loads(result.stdout)["idle"]
        self.assertIn("stayAwake", idle)
        self.assertIn("screensaverOff", idle)
        self.assertFalse(list(self.shell.parent.iterdir()))


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.scripts = self.root / "scripts"
        self.scripts.mkdir()
        shutil.copy(REPO / "scripts/aranea-settings", self.scripts)
        shutil.copytree(REPO / "scripts/lib", self.scripts / "lib")
        self.env = dict(
            os.environ,
            OWNER_LOG=str(self.root / "owner.log"),
            OWNER_STATE=str(self.root / "owner.json"),
        )
        for name in (
            "aranea-motion",
            "aranea-wallpaper",
            "aranea-integrations",
            "aranea-fonts",
        ):
            helper = self.scripts / name
            helper.write_text('#!/bin/sh\necho "{}"\nexit 1\n')
            helper.chmod(0o755)
        owner = self.scripts / "aranea-screensaver"
        owner.write_text("""#!/bin/sh
printf '%s\\n' "$*" >> "$OWNER_LOG"
case "$1" in
preview-scene) echo '{"accepted":true,"sessionId":null,"delegated":"stock"}' ;;
configure-idle) echo '{"idle":{"screensaverSeconds":31,"lockSeconds":89},"timingUpdate":{"persisted":true,"applied":true,"error":null},"error":"unrelated preference unreadable"}' | tee "$OWNER_STATE" ;;
status) if [ -f "$OWNER_STATE" ]; then
  if [ "${FAIL_READBACK:-0}" = 1 ]; then echo '{"idle":null}'; else cat "$OWNER_STATE"; fi
  exit
fi
;;
esac
case "$1" in
configure-idle|preview-scene) ;;
*) echo '{"availability":"available","selectedId":"silk-journey","mode":"single","idle":{"screensaverSeconds":900,"lockSeconds":1200},"error":null}' ;;
esac
""")
        owner.chmod(0o755)

    def run_adapter(self, *args):
        result = subprocess.run(
            [str(self.scripts / "aranea-settings"), *args, "--json"],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        return result, json.loads(result.stdout)

    def test_scene_apply_and_preview_use_exact_argv_despite_other_section_errors(self):
        result, data = self.run_adapter(
            "configure", "screensaver", "silk-journey", "single"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(data["ok"])
        self.assertEqual(data["schemaVersion"], 1)
        self.assertEqual(data["state"]["screensaver"]["selectedId"], "silk-journey")
        result, data = self.run_adapter("preview", "screensaver", "omarchy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(data["result"]["screensaverPreview"]["accepted"])
        self.assertEqual(data["result"]["screensaverPreview"]["delegated"], "stock")
        log = (self.root / "owner.log").read_text().splitlines()
        self.assertIn("configure silk-journey single --json", log)
        self.assertIn("preview-scene omarchy --json", log)

    def test_timing_has_independent_result_and_authoritative_readback(self):
        result, data = self.run_adapter("configure", "screensaver-timing", "31", "89")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(data["ok"])
        self.assertEqual(data["state"]["screensaver"]["idle"]["screensaverSeconds"], 31)
        self.assertTrue(data["result"]["screensaverTiming"]["persisted"])
        self.assertIn(
            "configure-idle 31 89 --json", (self.root / "owner.log").read_text()
        )

    def test_failed_timing_readback_cannot_claim_success(self):
        self.env["FAIL_READBACK"] = "1"
        result, data = self.run_adapter("configure", "screensaver-timing", "31", "89")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "READBACK_FAILED")
        self.assertTrue(data["result"]["screensaverTiming"]["persisted"])

    def test_extra_arguments_never_dispatch_mutation(self):
        result, data = self.run_adapter(
            "configure", "screensaver-timing", "31", "89", "extra"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(data["ok"])
        self.assertNotIn("configure-idle", (self.root / "owner.log").read_text())


if __name__ == "__main__":
    unittest.main()
