#!/usr/bin/env python3
"""Install only when explicitly run. Credentials stay out of the launchd plist."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys
from vibewatch import DEFAULT_CONFIG, load_config, private_write

parser = argparse.ArgumentParser()
parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
parser.add_argument('--uninstall', action='store_true')
args = parser.parse_args()
label = 'dev.vibewatch.collector'
plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
domain = f'gui/{os.getuid()}'
if args.uninstall:
    subprocess.run(['launchctl', 'bootout', domain + '/' + label], check=False, capture_output=True)
    plist.unlink(missing_ok=True)
    print('已停止并移除采集任务；私有配置保留')
else:
    config = load_config(args.config)
    log_dir = args.config.resolve().parent / 'logs'
    log_dir.mkdir(exist_ok=True, mode=0o700)
    data = {
        'Label': label,
        'ProgramArguments': [sys.executable, str(Path(__file__).with_name('vibewatch.py').resolve()), '--config', str(args.config.resolve()), 'run'],
        'EnvironmentVariables': {'PATH': str(Path(config['codex']).parent) + ':/opt/homebrew/bin:/usr/bin:/bin'},
        'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 60,
        'StandardOutPath': str(log_dir / 'collector.log'),
        'StandardErrorPath': str(log_dir / 'collector-error.log'),
    }
    private_write(plist, plistlib.dumps(data).decode())
    subprocess.run(['launchctl', 'bootout', domain + '/' + label], check=False, capture_output=True)
    subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], check=True)
    print('采集任务已安装；Mac 登录且唤醒时运行')
