#!/usr/bin/env python3
"""Prepare private, local-only credentials without printing their values."""
import json
from pathlib import Path
import secrets
import shutil
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT / 'agent'))
from vibewatch import private_write
secret_file = ROOT / 'cloud/.dev.vars'
if not secret_file.exists():
    private_write(secret_file, 'UPLOAD_TOKEN=' + secrets.token_hex(32) + '\n')
values = dict(line.strip().split('=',1) for line in secret_file.read_text().splitlines() if line.strip() and not line.startswith('#'))
token = values['UPLOAD_TOKEN'].strip('"\'')
config = ROOT / 'artifacts/local/config.json'
private_write(config,json.dumps({
    'server':'http://127.0.0.1:8787', 'uploadToken':token,
    'codex':shutil.which('codex') or 'codex', 'intervalSeconds':120,'heartbeatSeconds':300,
},indent=2))
print('本地配置已准备：artifacts/local/config.json；密钥未输出，不用于线上部署。')
