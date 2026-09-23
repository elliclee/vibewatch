#!/usr/bin/env python3
"""Round-trip a quota snapshot through a running local Worker; --real reads Codex."""
import argparse
import asyncio
import json
from pathlib import Path
import sys
import time
import urllib.request
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT / 'agent'))
from vibewatch import api, collect, load_config, NoRedirect
parser=argparse.ArgumentParser()
parser.add_argument('--real',action='store_true',help='使用本机真实额度，但仅上传到本地 Worker')
args=parser.parse_args()
config=load_config(ROOT / 'artifacts/local/config.json')
assert config['server']=='http://127.0.0.1:8787', 'Smoke test requires loopback'
if args.real:
    snapshot=asyncio.run(collect(config['codex']))
else:
    snapshot=json.loads((ROOT / 'contracts/snapshot.example.json').read_text())
    snapshot['collectedAt']=int(time.time())
api(config,'PUT','/v1/snapshot',snapshot)
pair=api(config,'POST','/v1/pairings',{'name':'local smoke (temporary)'})
try:
    request=urllib.request.Request(config['server']+'/v1/pairings/redeem',
        data=json.dumps({'code':pair['code']}).encode(),headers={'Content-Type':'application/json'})
    with urllib.request.build_opener(NoRedirect()).open(request,timeout=20) as response:
        token=json.load(response)['token']
    request=urllib.request.Request(config['server']+'/v1/snapshot',headers={'Authorization':'Bearer '+token})
    with urllib.request.build_opener(NoRedirect()).open(request,timeout=20) as response:
        result=json.load(response)
    assert result['snapshot']==snapshot, 'Snapshot did not round-trip'
    assert result['receivedAt']>=snapshot['collectedAt']-60
    print('本地闭环通过：采集/样例 → 认证上传 → 一次性配对 → 只读查询；未输出令牌或额度内容。')
finally:
    api(config,'DELETE','/v1/devices/'+pair['deviceId'])
