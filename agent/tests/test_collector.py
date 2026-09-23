import asyncio
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from vibewatch import VibeWatchError, collect, fingerprint, needs_upload, normalize, private_write, run_once, validate_server


class CollectorTests(unittest.TestCase):
    def sample(self):
        return {'rateLimitsByLimitId': {
            'codex': {'primary': {'usedPercent': 0, 'windowDurationMins': 300}},
            'other': {'primary': None, 'secondary': {'usedPercent': 68, 'resetsAt': 1800000000}},
        }, 'ordinaryUsageAllowed': False, 'accountId': 'must-not-leave-mac'}

    def test_multibucket_missing_and_zero_are_distinct(self):
        value = normalize(self.sample(), 100)
        self.assertEqual(len(value['buckets']), 2)
        self.assertEqual(value['buckets'][0]['primary']['usedPercent'], 0)
        self.assertIsNone(value['buckets'][0]['primary']['resetsAt'])
        self.assertIsNone(value['buckets'][1]['primary'])
        self.assertFalse(value['ordinaryUsageAllowed'])
        self.assertNotIn('must-not-leave-mac', json.dumps(value))

    def test_legacy_and_unknown_usage(self):
        value = normalize({'rateLimits': {'limitId': None}}, 100)
        self.assertEqual(value['buckets'][0]['limitId'], 'codex')
        self.assertIsNone(value['ordinaryUsageAllowed'])

    def test_invalid_numeric_fields(self):
        for invalid in (float('nan'), True, -1, 101, '20'):
            with self.subTest(invalid=invalid), self.assertRaises(VibeWatchError):
                normalize({'rateLimits': {'primary': {'usedPercent': invalid}}}, 100)

    def test_heartbeats_and_changed_data(self):
        value = normalize(self.sample(), 100)
        state = {'fingerprint': fingerprint(value), 'uploadedAt': 100}
        value['collectedAt'] = 200
        self.assertFalse(needs_upload(value, state, 200, 300))
        self.assertTrue(needs_upload(value, state, 400, 300))
        value['buckets'][0]['primary']['usedPercent'] = 1
        self.assertTrue(needs_upload(value, state, 200, 300))

    def test_upload_failure_does_not_update_heartbeat(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / 'state.json'
            private_write(state, '{"uploadedAt": 100}')
            async def fake_collect(_): return normalize(self.sample(), 200)
            with patch('vibewatch.collect', fake_collect), patch('vibewatch.api', side_effect=VibeWatchError('offline')):
                with self.assertRaises(VibeWatchError):
                    run_once({'codex':'codex','heartbeatSeconds':300}, state)
            self.assertEqual(json.loads(state.read_text()), {'uploadedAt':100})
            self.assertEqual(state.stat().st_mode & 0o777, 0o600)

    def test_https_and_redirect_input_restrictions(self):
        self.assertEqual(validate_server('https://example.com/'), 'https://example.com')
        self.assertEqual(validate_server('http://127.0.0.1:8787'), 'http://127.0.0.1:8787')
        for server in ('http://example.com', 'https://user:pass@example.com', 'https://example.com/a', 'https://example.com?token=x'):
            with self.assertRaises(VibeWatchError): validate_server(server)

    def test_app_server_handshake_notifications_and_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'fake-codex'
            binary.write_text('''#!/usr/bin/env python3
import sys,json
m=json.loads(sys.stdin.readline()); assert m['method']=='initialize'
print(json.dumps({'id':1,'result':{}}),flush=True)
assert json.loads(sys.stdin.readline())['method']=='initialized'
assert json.loads(sys.stdin.readline())['method']=='account/rateLimits/read'
print(json.dumps({'method':'noise','params':{}}),flush=True)
print(json.dumps({'id':2,'result':{'rateLimits':{'limitId':'codex'}}}),flush=True)
sys.stdin.read()
''')
            binary.chmod(0o700)
            result = asyncio.run(collect(str(binary), timeout=3))
            self.assertEqual(result['buckets'][0]['limitId'], 'codex')

    def test_timeout_terminates_the_app_server(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'fake-codex'
            pid_path = Path(directory) / 'pid'
            binary.write_text('#!/usr/bin/env python3\nimport os,time\nfrom pathlib import Path\n'
                              + f'Path({str(pid_path)!r}).write_text(str(os.getpid()))\n'
                              + 'time.sleep(30)\n')
            binary.chmod(0o700)
            with self.assertRaises(asyncio.TimeoutError):
                asyncio.run(collect(str(binary), timeout=0.3))
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pid_path.read_text()), 0)

    def test_collection_failure_does_not_upload_or_renew_state(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / 'state.json'
            private_write(state, '{"uploadedAt": 100}')
            async def failing_collect(_): raise VibeWatchError('unavailable')
            with patch('vibewatch.collect', failing_collect), patch('vibewatch.api') as upload:
                with self.assertRaises(VibeWatchError):
                    run_once({'codex':'codex','heartbeatSeconds':300}, state)
                upload.assert_not_called()
            self.assertEqual(json.loads(state.read_text()), {'uploadedAt':100})


if __name__ == '__main__': unittest.main()
