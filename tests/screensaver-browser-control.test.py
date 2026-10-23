"""Exercise browser crash monitoring through real, private OS pipes."""

import importlib
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


class BrowserControlTests(unittest.TestCase):
    def setUp(self):
        self.module = importlib.import_module('tools.screensaver.browser_control')
        self.control = self.module.BrowserControl()
        self.addCleanup(self.control.close)
        self.browser_read, self.browser_write = [os.dup(fd) for fd in self.control.child_fds]
        self.addCleanup(os.close, self.browser_read)
        self.addCleanup(lambda: os.close(self.browser_write) if self.browser_write is not None else None)
        self.pending = b''
        self.control.started()
        self.discovery = self.command()
        self.assertEqual(self.discovery['method'], 'Target.setDiscoverTargets')
        self.assertEqual(self.discovery['params'], {'discover': True})

    def command(self):
        deadline = time.monotonic() + 1
        while b'\0' not in self.pending:
            self.assertLess(time.monotonic(), deadline, 'browser command unavailable')
            self.assertTrue(select.select([self.browser_read], [], [], .5)[0])
            self.pending += os.read(self.browser_read, 65536)
        value, self.pending = self.pending.split(b'\0', 1)
        return json.loads(value)

    def send(self, value):
        os.write(self.browser_write, json.dumps(value).encode() + b'\0')

    def connected(self):
        self.send({'id': self.discovery['id'], 'result': {}})
        self.send({'method': 'Target.targetCreated', 'params': {'targetInfo': {'targetId': 'page-1', 'type': 'page'}}})
        self.assertEqual(self.control.poll(), [])
        self.assertTrue(self.control.connected)

    def crash(self, **changes):
        params = {'targetId': 'page-1', 'status': 'killed', 'errorCode': 9}
        params.update(changes)
        self.send({'method': 'Target.targetCrashed', 'params': params})

    def test_connected_requires_discovery_ack_and_page_target(self):
        self.assertFalse(self.control.connected)
        self.send({'id': self.discovery['id'], 'result': {}})
        self.control.poll()
        self.assertFalse(self.control.connected)
        self.send({'method': 'Target.targetCreated', 'params': {'targetInfo': {'targetId': 'page-1', 'type': 'page'}}})
        self.control.poll()
        self.assertTrue(self.control.connected)

    def test_page_crash_preserves_browser_status_and_exit_code(self):
        self.connected()
        self.crash()
        events = self.control.poll()
        self.assertEqual(len(events), 1)
        self.assertEqual((events[0].target_id, events[0].status, events[0].error_code), ('page-1', 'killed', 9))
        self.assertEqual(self.control.poll(), [])

    def test_unrelated_worker_crash_and_normal_page_close_do_not_reload(self):
        self.connected()
        self.send({'method': 'Target.targetCreated', 'params': {'targetInfo': {'targetId': 'worker-1', 'type': 'worker'}}})
        self.crash(targetId='worker-1')
        self.send({'method': 'Target.targetDestroyed', 'params': {'targetId': 'page-1'}})
        self.assertEqual(self.control.poll(), [])
        self.assertFalse(select.select([self.browser_read], [], [], 0)[0])

    def test_fragmented_null_framed_messages_are_not_lost(self):
        self.connected()
        raw = json.dumps({'method': 'Target.targetCrashed', 'params': {'targetId': 'page-1', 'status': 'crashed', 'errorCode': 11}}).encode() + b'\0'
        os.write(self.browser_write, raw[:19])
        self.assertEqual(self.control.poll(), [])
        os.write(self.browser_write, raw[19:])
        self.assertEqual(self.control.poll()[0].error_code, 11)

    def test_reload_attaches_only_the_owned_page_and_uses_flat_session(self):
        self.connected()
        self.control.reload('page-1')
        attach = self.command()
        self.assertEqual((attach['method'], attach['params']), ('Target.attachToTarget', {'targetId': 'page-1', 'flatten': True}))
        self.send({'id': attach['id'], 'result': {'sessionId': 'owned-session'}})
        self.assertEqual(self.control.poll(), [])
        reload = self.command()
        self.assertEqual((reload['method'], reload['params'], reload['sessionId']), ('Page.reload', {}, 'owned-session'))
        self.send({'id': reload['id'], 'result': {}})
        self.assertEqual(self.control.poll(), [])
        with self.assertRaises(ValueError):
            self.control.reload('unknown-page')

    def test_discovery_and_recovery_errors_fail_closed(self):
        self.send({'id': self.discovery['id'], 'error': {'message': 'unavailable'}})
        with self.assertRaisesRegex(ValueError, 'browser|Browser'):
            self.control.poll()

    def test_malformed_crash_status_and_code_are_rejected(self):
        self.connected()
        for changes in ({'status': 'crashed\nforged'}, {'status': None}, {'errorCode': True}, {'errorCode': 2**40}):
            with self.subTest(changes=changes):
                self.crash(**changes)
                with self.assertRaises(ValueError):
                    self.control.poll()

    def test_protocol_frames_are_bounded_and_json_must_be_an_object(self):
        self.connected()
        for raw in (b'[]\0', b'\xff\0', b'invalid\0'):
            os.write(self.browser_write, raw)
            with self.assertRaises(ValueError):
                self.control.poll()
        os.write(self.browser_write, b'x' * 4096)
        self.assertEqual(self.control.poll(), [])
        # Feed incrementally to avoid blocking the fake browser's pipe writer.
        for _ in range(17):
            os.write(self.browser_write, b'x' * 4096)
            try:
                self.control.poll()
            except ValueError:
                break
        else:
            self.fail('Unbounded browser protocol frame accepted')

    def test_disconnection_is_detected_and_close_is_idempotent(self):
        self.connected()
        # The duplicated child write end is the last remaining writer.
        os.close(self.browser_write)
        self.browser_write = None
        self.assertFalse(self.control.closed)
        with self.assertRaisesRegex(ValueError, 'disconnect|closed'):
            self.control.poll()
        self.control.close()
        self.control.close()
        self.assertTrue(self.control.closed)


class BrowserLauncherTests(unittest.TestCase):
    def test_exec_preserves_pipe_fds_when_both_sources_are_above_fd_four(self):
        fillers = [os.open(os.devnull, os.O_RDONLY) for _ in range(10)]
        incoming, writer = os.pipe()
        reader, outgoing = os.pipe()
        process = None
        try:
            process = subprocess.Popen(
                [sys.executable, str(ROOT / "tools/screensaver/browser_control.py"), str(incoming), str(outgoing), sys.executable, "-c", "import os;os.write(4,os.read(3,4))"],
                pass_fds=(incoming, outgoing), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            os.write(writer, b"ping")
            stdout, stderr = process.communicate(timeout=3)
            self.assertEqual(process.returncode, 0, stderr.decode())
            self.assertEqual(os.read(reader, 4), b"ping")
        finally:
            if process is not None and process.poll() is None:
                process.kill(); process.wait(timeout=3)
            for fd in (*fillers, incoming, writer, reader, outgoing):
                os.close(fd)


if __name__ == '__main__':
    unittest.main()
