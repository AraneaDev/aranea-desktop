"""Temporary CI evidence collection; no host session or persistent profile."""
import importlib.util
import os
import resource
from pathlib import Path
import subprocess
import sys
import time
import unittest

root = Path(__file__).resolve().parents[1]
binary = sys.argv[1]
print("BROWSER", binary, "REALPATH", os.path.realpath(binary), flush=True)
spec = importlib.util.spec_from_file_location("cursor_diagnostic", root / "tests/screensaver-cursor.test.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.BROWSER = binary
original = subprocess.Popen
class Capture(original):
    def communicate(self, *args, **kwargs):
        try:
            result = super().communicate(*args, **kwargs)
            print("COMPLETED_STDERR", result[1], flush=True)
            print("COMPLETED_STDOUT", result[0], flush=True)
            return result
        except subprocess.TimeoutExpired as error:
            print("TIMEOUT browser_pid", self.pid, "poll", self.poll(), flush=True)
            for entry in Path("/proc").iterdir():
                if not entry.name.isdigit():
                    continue
                try:
                    stat = (entry / "stat").read_text().split(") ", 1)[1].split()
                    if int(stat[2]) == self.pid:
                        print("OWNED_PROCESS", entry.name, stat[:8], flush=True)
                except (OSError, ValueError, IndexError):
                    pass
            for label, value in (("STDOUT", error.stdout), ("STDERR", error.stderr)):
                if isinstance(value, bytes):
                    value = value.decode("utf-8", errors="replace")
                print(label, value, flush=True)
            raise
subprocess.Popen = Capture
results = []
for attempt in range(1):
    started = time.monotonic()
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(module))
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    print("RESOURCES", {name: getattr(after, name) - getattr(before, name) for name in ("ru_utime", "ru_stime", "ru_majflt", "ru_minflt", "ru_inblock")}, flush=True)
    results.append(result.wasSuccessful())
    print("ATTEMPT", attempt + 1, "SUCCESS", result.wasSuccessful(), "SECONDS", time.monotonic() - started, flush=True)
print("VERSION", subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=10).stdout.strip(), flush=True)
print("RESULTS", results, flush=True)
sys.exit(0 if all(results) else 1)
