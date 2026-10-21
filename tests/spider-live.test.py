"""Local scene asset isolation, browser failure and preview lifetime tests."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "spider_preview", ROOT / "tools/spider/preview.py"
)
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class PreviewTests(unittest.TestCase):
    def test_public_assets_only(self):
        for url in [
            "/live/",
            "/live/scene.mjs",
            "/live/vendor/three.module.js",
            "/aranea-spider.glb",
        ]:
            self.assertIsNotNone(preview.asset_path(url))
        for url in [
            "/README.md",
            "/aranea-spider.blend",
            "/live/../aranea-spider.blend",
            "/live/%2e%2e/aranea-spider.blend",
            "/live/%5c../README.md",
            "/live/%00",
            "/.git/config",
        ]:
            self.assertIsNone(preview.asset_path(url), url)

    def run_browser(self, mode):
        with tempfile.TemporaryDirectory(prefix="aranea-preview-test-") as folder:
            folder = Path(folder)
            browser = folder / "fake chromium"
            record = folder / "browser.json"
            browser.write_text("""#!/usr/bin/env python3
import json,os,sys,time
from urllib.parse import urlsplit,parse_qs
from urllib.request import Request,urlopen
from urllib.error import HTTPError
args=sys.argv[1:]
url=next(a[6:] for a in args if a.startswith('--app='))
profile=next(a.split('=',1)[1] for a in args if a.startswith('--user-data-dir='))
open(os.environ['SPIDER_TEST_RECORD'],'w').write(json.dumps({'profile':profile,'url':url}))
mode=os.environ['SPIDER_TEST_MODE']
if mode=='failure': sys.exit(7)
if mode=='dismiss':
 base=url.split('/live/')[0]
 try: urlopen(Request(base+'/__dismiss',method='POST'))
 except HTTPError as e: assert e.code==403
 else: raise AssertionError('unauthenticated dismissal accepted')
 assert urlopen(url).status==200
 token=parse_qs(urlsplit(url).query)['session'][0]
 assert urlopen(Request(base+'/__dismiss',method='POST',headers={'X-Aranea-Session':token})).status==204
 time.sleep(8)
""")
            browser.chmod(0o755)
            env = dict(
                os.environ, SPIDER_TEST_RECORD=str(record), SPIDER_TEST_MODE=mode
            )
            result = subprocess.run(
                [
                    "python3",
                    str(ROOT / "tools/spider/preview.py"),
                    "--browser",
                    str(browser),
                ],
                env=env,
                capture_output=True,
                text=True,
                timeout=12,
            )
            data = json.loads(record.read_text())
            self.assertFalse(
                Path(data["profile"]).exists(), "temporary browser profile leaked"
            )
            self.assertIn("127.0.0.1:", data["url"])
            return result

    def test_normal_close(self):
        self.assertEqual(self.run_browser("normal").returncode, 0)

    def test_startup_failure_is_reported(self):
        self.assertNotEqual(self.run_browser("failure").returncode, 0)

    def test_authenticated_dismissal(self):
        self.assertEqual(self.run_browser("dismiss").returncode, 0)


if __name__ == "__main__":
    unittest.main()
