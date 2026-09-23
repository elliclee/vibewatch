import datetime as dt
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from usage import collect_usage


class UsageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        (self.root / 'sessions').mkdir()
        self.now = int(time.time())
        self.start = int(dt.datetime.fromtimestamp(self.now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
        self.now = max(self.now, self.start + 3600)

    def tearDown(self): self.tmp.cleanup()

    def event(self, stamp, total, last=None):
        def fields(v): return dict(zip(['input_tokens','cached_input_tokens','output_tokens'], v))
        return {'timestamp': dt.datetime.fromtimestamp(stamp, dt.timezone.utc).isoformat(), 'type': 'event_msg',
                'payload': {'type': 'token_count', 'info': {'total_token_usage': fields(total), 'last_token_usage': fields(last or total)}}}

    def write(self, name, records):
        p = self.root / 'sessions' / name
        p.write_text(''.join(json.dumps(x)+'\n' for x in records)); os.utime(p, (self.now,self.now)); return p

    def test_cached_input_not_double_counted_and_duplicate_events_ignored(self):
        e = self.event(self.start+100, [100,40,20])
        self.write('a.jsonl',[e,e]);self.write('fork.jsonl',[e])
        result=collect_usage(self.root,self.now)
        self.assertEqual([result[k] for k in ['inputTokens','cachedInputTokens','outputTokens','totalTokens']],[60,40,20,120])
        self.assertEqual(sum(h['tokens'] for h in result['hours']),120)

    def test_midnight_uses_previous_cumulative_baseline(self):
        self.write('a.jsonl',[self.event(self.start-100,[100,40,20]),self.event(self.start+100,[150,50,30],[50,10,10])])
        r=collect_usage(self.root,self.now)
        self.assertEqual(r['totalTokens'],60);self.assertEqual(r['inputTokens'],40)

    def test_incremental_append_and_incomplete_record(self):
        cache=self.root/'cache.json';p=self.write('a.jsonl',[self.event(self.start+100,[100,40,20])])
        first=collect_usage(self.root,self.now,cache)
        self.assertEqual(first,collect_usage(self.root,self.now,cache))
        e=json.dumps(self.event(self.start+200,[150,50,30],[50,10,10]))
        with p.open('a') as f:f.write(e)
        self.assertEqual(collect_usage(self.root,self.now,cache)['totalTokens'],120)
        with p.open('a') as f:f.write('\n')
        self.assertEqual(collect_usage(self.root,self.now,cache)['totalTokens'],180)
        self.assertEqual(cache.stat().st_mode & 0o777,0o600)

    def test_reset_uses_last_usage_and_marks_partial(self):
        self.write('a.jsonl',[self.event(self.start+100,[100,40,20]),self.event(self.start+200,[10,5,3])])
        r=collect_usage(self.root,self.now);self.assertEqual(r['totalTokens'],133);self.assertTrue(r['partial'])

    def test_no_counters_is_unavailable_and_no_conversation_exported(self):
        self.write('a.jsonl',[{'type':'response_item','payload':{'text':'PRIVATE_PROMPT'}}])
        self.assertIsNone(collect_usage(self.root,self.now))
        e=self.event(self.start+100,[100,40,20]);e['payload']['secret']='PRIVATE_PROMPT'
        self.write('a.jsonl',[e]);self.assertNotIn('PRIVATE_PROMPT',json.dumps(collect_usage(self.root,self.now)))
