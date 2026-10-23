"""Check actual browser cursor inheritance during all screensaver page states."""

import html
import json
from pathlib import Path
import re
import os
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))
from tools.screensaver.renderers import OwnedProcess, terminate_group

BROWSER = next((path for path in ("/usr/lib/chromium/chromium", "/usr/bin/chromium", "/opt/google/chrome/chrome", "/usr/bin/google-chrome") if os.access(path, os.X_OK)), None)


@unittest.skipUnless(BROWSER, "Chromium is unavailable for cursor behavior")
class CursorTests(unittest.TestCase):
    def test_loading_ready_error_descendants_and_keyboard_dismissal(self):
        style = (REPO / "branding/3d/collection/ambient/style.css").read_text()
        bootstrap = (REPO / "branding/3d/live/dismiss.js").read_text()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            page = root / "cursor.html"
            page.write_text(
                "<!doctype html><html><head><style>" + style + "</style></head>"
                '<body><canvas></canvas><div id="status">Loading</div>'
                '<span style="cursor:crosshair">Overlay</span><script>'
                'window.fetch=async(url)=>{document.body.dataset.notice=url;return {ok:true}};'
                'window.close=()=>{document.body.dataset.closed="true"};'
                'const initial=getComputedStyle(document.body).cursor;'
                "</script><script>" + bootstrap + "</script><script>"
                'const nodes=[document.documentElement,document.body,...document.querySelectorAll("canvas,#status,span")];'
                'const sample=()=>nodes.map(node=>getComputedStyle(node).cursor);'
                'const loading=sample();document.body.dataset.ready="true";'
                'const ready=sample();document.body.dataset.error="test";const error=sample();'
                'setTimeout(()=>{window.dispatchEvent(new KeyboardEvent("keydown",{key:"Escape"}));'
                'setTimeout(()=>{document.body.dataset.probe=JSON.stringify({initial,loading,ready,error,closed:document.body.dataset.closed,notice:document.body.dataset.notice})},20)},20);'
                "</script></body></html>"
            )
            process = subprocess.Popen(
                [BROWSER, "--headless=new", "--no-sandbox", "--disable-gpu",
                 "--disable-extensions", "--no-first-run", "--no-default-browser-check",
                 "--disable-background-networking", "--disable-component-update", "--disable-sync",
                 f"--user-data-dir={root / 'profile'}", "--virtual-time-budget=1000",
                 "--dump-dom", page.as_uri()],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
            )
            owned = OwnedProcess(process, process.pid)
            try:
                # A cold CI browser can block on filesystem page reads before loading
                # this tiny fixture; its virtual-time budget still stays at 1s.
                stdout, stderr = process.communicate(timeout=90)
            except subprocess.TimeoutExpired as error:
                def partial(value):
                    if isinstance(value, bytes):
                        value = value.decode("utf-8", errors="replace")
                    return (value or "")[-4000:]

                self.fail(
                    f"Browser did not finish within 90 seconds: {Path(BROWSER).resolve()} "
                    f"(exit={process.poll()!r})\n"
                    f"Partial stderr:\n{partial(error.stderr)}\n"
                    f"Partial stdout:\n{partial(error.stdout)}"
                )
            finally:
                terminate_group(owned)
            self.assertEqual(process.returncode, 0, stderr[-2000:])
            match = re.search(r'data-probe="([^"]+)"', stdout)
            self.assertIsNotNone(match, stdout[-2000:])
            probe = json.loads(html.unescape(match[1]))
            self.assertEqual(probe["initial"], "none", "cursor must hide before WebGL loads")
            for state in ("loading", "ready", "error"):
                self.assertEqual(probe[state], ["none"] * 5, state)
            self.assertEqual(probe["closed"], "true")
            self.assertEqual(probe["notice"], "/__dismiss")


if __name__ == "__main__":
    unittest.main()
