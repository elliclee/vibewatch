"""Local Codex token counters only. Never retain or upload conversation payloads."""
import datetime as dt
import hashlib
import json
import re
from pathlib import Path

FIELDS = ('input_tokens', 'cached_input_tokens', 'output_tokens')


def counters(value):
    if not isinstance(value, dict): return None
    values = [value.get(k) for k in FIELDS]
    if any(type(x) is not int or not 0 <= x <= 10**15 for x in values): return None
    return values if values[1] <= values[0] else None


def label(value):
    return value if isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_.:/-]{1,80}', value) else None


def read_file(path, previous, start, end):
    stat = path.stat()
    state = previous if previous and previous['offset'] <= stat.st_size and previous['inode'] == stat.st_ino else {
        'offset': 0, 'inode': stat.st_ino, 'total': None, 'events': [], 'model': None,
        'effort': None, 'activity': None, 'partial': False, 'observed': False}
    with path.open('rb') as stream:
        stream.seek(state['offset'])
        for line in stream:
            if not line.endswith(b'\n'): break  # Retry an unfinished record next time.
            state['offset'] += len(line)
            if b'"token_count"' not in line and b'"turn_context"' not in line: continue
            try:
                record = json.loads(line)
                stamp = dt.datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00')).timestamp()
                payload = record.get('payload', {})
                if record.get('type') == 'turn_context':
                    state['model'] = label(payload.get('model'))
                    state['effort'] = label(payload.get('effort') or payload.get('reasoning_effort'))
                    continue
                if record.get('type') != 'event_msg' or payload.get('type') != 'token_count': continue
                info = payload.get('info') or {}
                total = counters(info.get('total_token_usage'))
                if total is None: continue
                old = state['total']; state['total'] = total; state['observed'] = True
                if old == total: continue  # Rate-limit-only updates repeat the same totals.
                delta = [a - b for a, b in zip(total, old)] if old else counters(info.get('last_token_usage'))
                if delta is None or any(x < 0 for x in delta) or delta[1] > delta[0]:
                    delta = counters(info.get('last_token_usage')); state['partial'] = True
                if old is None and delta != total: state['partial'] = True
                if delta is None or not start <= stamp < end: continue
                key = hashlib.sha256(json.dumps([stamp, total, info.get('last_token_usage')], sort_keys=True).encode()).hexdigest()
                state['events'].append([key, stamp, *delta])
                state['activity'] = [stamp, state['model'], state['effort']]
            except (ValueError, TypeError, KeyError, AttributeError):
                state['partial'] = True
    return state


def collect_usage(root, now, cache_path=None):
    """Aggregate this Mac's local day. Input is split into uncached input + cache.

    Incremental state contains only numeric counters, safe labels and local file keys.
    Identical inherited events in forked/archived sessions count once.
    """
    local = dt.datetime.fromtimestamp(now).astimezone()
    midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
    start = int(midnight.timestamp())
    # mktime applies the machine's local timezone rules at the following midnight.
    import time
    tomorrow = midnight.date() + dt.timedelta(days=1)
    end = int(time.mktime((*tomorrow.timetuple()[:3], 0, 0, 0, 0, 0, -1)))
    cached = {}
    if cache_path and cache_path.exists():
        try:
            saved = json.loads(cache_path.read_text())
            if saved.get('start') == start: cached = saved.get('files', {})
        except (ValueError, OSError): pass
    files = {}
    partial = False
    for directory in ('sessions', 'archived_sessions'):
        folder = Path(root) / directory
        if not folder.exists(): continue
        for path in folder.rglob('*.jsonl'):
            try:
                if path.is_symlink() or path.stat().st_mtime < start: continue
                key = str(path.relative_to(root))
                files[key] = read_file(path, cached.get(key), start, min(end, now + 1))
            except OSError: partial = True
    if cache_path:
        from vibewatch import private_write
        private_write(cache_path, json.dumps({'start': start, 'files': files}, separators=(',', ':')))
    observed = any(s['observed'] for s in files.values())
    if not observed: return None
    hours = [{'start': t, 'tokens': 0} for t in range(start, end, 3600)]
    seen = set(); totals = [0, 0, 0]; activity = None
    for state in files.values():
        partial |= state['partial']
        if state['activity'] and (activity is None or state['activity'][0] > activity[0]): activity = state['activity']
        for key, stamp, inp, cache, out in state['events']:
            if key in seen: continue
            seen.add(key)
            totals = [totals[0] + inp, totals[1] + cache, totals[2] + out]
            hours[min(len(hours) - 1, int((stamp - start) // 3600))]['tokens'] += inp + out
    inp, cache, out = totals
    return {'periodStart': start, 'periodEnd': end, 'utcOffsetMinutes': int(local.utcoffset().total_seconds() / 60),
            'inputTokens': inp - cache, 'cachedInputTokens': cache, 'outputTokens': out,
            'totalTokens': inp + out, 'hours': hours, 'source': 'local', 'partial': partial,
            'model': activity[1] if activity else None, 'reasoningEffort': activity[2] if activity else None,
            'lastActivityAt': int(activity[0]) if activity else None}
