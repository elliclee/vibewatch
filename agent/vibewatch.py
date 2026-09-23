#!/usr/bin/env python3
"""VibeWatch collector. Only quota summaries leave the Mac; stdlib only."""
import argparse
import asyncio
import base64
import fcntl
import getpass
import hashlib
import html
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_CONFIG = Path.home() / 'Library/Application Support/VibeWatch/config.json'
USER_AGENT = 'VibeWatch/0.1'


class VibeWatchError(Exception):
    pass


def numeric(value, minimum, maximum, integer=False):
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise VibeWatchError('额度字段类型不正确')
    if not minimum <= value <= maximum or (integer and int(value) != value):
        raise VibeWatchError('额度字段超出协议范围')
    return value


def normalize_window(value):
    if value is None:
        return None
    if not isinstance(value, dict):
        raise VibeWatchError('窗口格式不正确')
    return {
        'usedPercent': numeric(value.get('usedPercent'), 0, 100),
        'windowDurationMins': numeric(value.get('windowDurationMins'), 1, 5256000, True),
        'resetsAt': numeric(value.get('resetsAt'), 0, 253402300799, True),
    }


def normalize(result, collected_at):
    buckets = result.get('rateLimitsByLimitId')
    if buckets is None or buckets == {}:
        legacy = result.get('rateLimits')
        if not isinstance(legacy, dict):
            raise VibeWatchError('没有可读取的账号额度；请检查 Codex 登录方式')
        buckets = {legacy.get('limitId') or 'codex': legacy}
    if not isinstance(buckets, dict) or not 1 <= len(buckets) <= 32:
        raise VibeWatchError('额度 bucket 格式不正确')
    output = []
    for limit_id, bucket in sorted(buckets.items()):
        if not isinstance(limit_id, str) or not limit_id.strip() or len(limit_id) > 128 or not isinstance(bucket, dict):
            raise VibeWatchError('额度 bucket 无效')
        name = bucket.get('limitName')
        if name is not None and (not isinstance(name, str) or len(name) > 128):
            raise VibeWatchError('额度名称无效')
        output.append({
            'limitId': limit_id, 'limitName': name,
            'primary': normalize_window(bucket.get('primary')),
            'secondary': normalize_window(bucket.get('secondary')),
        })
    allowed = result.get('ordinaryUsageAllowed')
    if allowed is not None and not isinstance(allowed, bool):
        raise VibeWatchError('额度可用状态无效')
    return {'schemaVersion': 1, 'collectedAt': collected_at, 'ordinaryUsageAllowed': allowed, 'buckets': output}


async def collect(codex='codex', timeout=30):
    process = await asyncio.create_subprocess_exec(
        codex, 'app-server', '--listen', 'stdio://',
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL, limit=1024 * 1024,
    )

    async def send(message):
        process.stdin.write((json.dumps(message) + '\n').encode())
        await process.stdin.drain()

    async def receive(request_id):
        while line := await process.stdout.readline():
            reply = json.loads(line)
            if reply.get('id') != request_id:
                continue
            if 'error' in reply:
                # Server errors can include account metadata; never echo them.
                raise VibeWatchError('Codex 额度读取失败；请在 Codex 中确认已登录')
            result = reply.get('result')
            if not isinstance(result, dict):
                raise VibeWatchError('Codex 返回了未知格式')
            return result
        raise VibeWatchError('Codex app-server 提前退出')

    async def exchange():
        await send({'id': 1, 'method': 'initialize', 'params': {
            'clientInfo': {'name': 'vibewatch', 'version': '0.1.0'}, 'capabilities': None,
        }})
        await receive(1)
        await send({'method': 'initialized', 'params': {}})
        await send({'id': 2, 'method': 'account/rateLimits/read', 'params': {}})
        return normalize(await receive(2), int(time.time()))

    try:
        return await asyncio.wait_for(exchange(), timeout)
    finally:
        if process.returncode is None:
            process.terminate()
        try:
            await asyncio.wait_for(process.wait(), 3)
        except asyncio.TimeoutError:
            process.kill()
            await process.wait()


def validate_server(value):
    url = urllib.parse.urlsplit(value)
    local = url.hostname in ('localhost', '127.0.0.1', '::1')
    if (url.scheme != 'https' and not (url.scheme == 'http' and local)) or not url.hostname:
        raise VibeWatchError('服务地址必须使用 HTTPS；仅本地回环联调允许 HTTP')
    if url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
        raise VibeWatchError('请填写不带路径或参数的云端服务地址')
    return value.rstrip('/')


def private_write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_name(path.name + '.tmp')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(value)
    os.replace(temp, path)


def load_config(path):
    path = Path(path).expanduser()
    if path.stat().st_mode & 0o077:
        raise VibeWatchError('配置文件权限过宽，请执行 chmod 600 后重试')
    value = json.loads(path.read_text())
    value['server'] = validate_server(value['server'])
    token = value.get('uploadToken')
    if not isinstance(token, str) or not 32 <= len(token) <= 256 or not token.isascii() or any(c.isspace() for c in token):
        raise VibeWatchError('上传密钥需要 32–256 个非空白 ASCII 字符')
    value.setdefault('codex', shutil.which('codex') or 'codex')
    value.setdefault('intervalSeconds', 120)
    value.setdefault('heartbeatSeconds', 300)
    if not 60 <= value['intervalSeconds'] <= 300 or not value['intervalSeconds'] <= value['heartbeatSeconds'] <= 600:
        raise VibeWatchError('采集间隔应为 60–300 秒，心跳应在采集间隔与 600 秒之间')
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward an authorization header to another endpoint.


def api(config, method, path, payload=None):
    headers = {'Authorization': 'Bearer ' + config['uploadToken'], 'Content-Type': 'application/json',
               'User-Agent': USER_AGENT}
    data = json.dumps(payload, separators=(',', ':'), allow_nan=False).encode() if payload is not None else None
    request = urllib.request.Request(config['server'] + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=20) as response:
            return json.loads(response.read(65537))
    except urllib.error.HTTPError as error:
        raise VibeWatchError(f'云端请求失败（HTTP {error.code}）') from None
    except urllib.error.URLError:
        raise VibeWatchError('无法连接云端，保留上次上传状态') from None


def fingerprint(snapshot):
    content = {k: v for k, v in snapshot.items() if k != 'collectedAt'}
    return hashlib.sha256(json.dumps(content, sort_keys=True).encode()).hexdigest()


def needs_upload(snapshot, state, now, heartbeat):
    return fingerprint(snapshot) != state.get('fingerprint') or now - state.get('uploadedAt', 0) >= heartbeat or now < state.get('uploadedAt', 0)


def run_once(config, state_path, force=False):
    snapshot = asyncio.run(collect(config['codex']))
    if config.get('includeLocalUsage', False):
        from usage import collect_usage
        usage = collect_usage(Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))),
                              snapshot['collectedAt'], state_path.with_name('usage-state.json'))
        if usage is not None: snapshot['usage'] = usage
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    now = int(time.time())
    if force or needs_upload(snapshot, state, now, config['heartbeatSeconds']):
        api(config, 'PUT', '/v1/snapshot', snapshot)
        private_write(state_path, json.dumps({'fingerprint': fingerprint(snapshot), 'uploadedAt': now}))
        print('额度采集并上传成功', flush=True)
    else:
        print('额度未变化，等待下次心跳', flush=True)


def create_pairing(config, name, output):
    pairing = api(config, 'POST', '/v1/pairings', {'name': name})
    link = 'vibewatch://pair?' + urllib.parse.urlencode({'server': config['server'], 'code': pairing['code']})
    qr_script = Path(__file__).with_name('qr.swift')
    qr = subprocess.run(['/usr/bin/swift', str(qr_script)], input=link.encode(), capture_output=True)
    if qr.returncode:
        raise VibeWatchError('无法生成配对二维码，请确认 Xcode Command Line Tools 已安装')
    picture = base64.b64encode(qr.stdout).decode()
    page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>VibeWatch 配对</title><body style="font:18px system-ui;text-align:center;padding:40px">
<h1>配对 VibeWatch</h1><p>在 iPhone App 中扫描，10 分钟内有效，仅可使用一次。</p>
<img width="360" height="360" alt="配对二维码" src="data:image/png;base64,{picture}">
<p>服务器：{html.escape(config['server'])}</p><p>也可在 iPhone 配对页粘贴此链接：</p>
<textarea readonly style="width:90%;height:100px">{html.escape(link)}</textarea>
<p>配对结束后删除本文件。</p></body></html>'''
    private_write(output, page)
    print(f'配对页面已保存到 {output}（未在终端输出配对码）')


def main():
    parser = argparse.ArgumentParser(description='VibeWatch Mac 额度采集器')
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    subs = parser.add_subparsers(dest='command', required=True)
    subs.add_parser('init', help='交互保存云端地址与上传密钥')
    subs.add_parser('probe', help='读取真实额度，仅输出 bucket 数和缺失窗口数')
    subs.add_parser('once', help='成功采集后立即上传')
    subs.add_parser('run', help='周期采集；变化或心跳时上传')
    pair = subs.add_parser('pair', help='生成一次性配对二维码文件')
    pair.add_argument('--name', default='iPhone + Watch')
    pair.add_argument('--output', type=Path, default=DEFAULT_CONFIG.parent / 'pairing.html')
    subs.add_parser('devices', help='列出已配对设备（不输出令牌）')
    revoke = subs.add_parser('revoke', help='撤销 iPhone / Watch 共享的只读凭据')
    revoke.add_argument('device_id')
    args = parser.parse_args()
    try:
        if args.command == 'init':
            if args.config.exists():
                raise VibeWatchError('配置已存在；请直接编辑私有配置文件')
            server = validate_server(input('HTTPS 服务地址：').strip())
            token = getpass.getpass('上传密钥（不回显）：').strip()
            if not 32 <= len(token) <= 256 or not token.isascii() or any(c.isspace() for c in token):
                raise VibeWatchError('上传密钥需要 32–256 个非空白 ASCII 字符')
            private_write(args.config, json.dumps({'server': server, 'uploadToken': token, 'codex': shutil.which('codex') or 'codex', 'intervalSeconds': 120, 'heartbeatSeconds': 300}, indent=2))
            print('已安全保存配置')
            return
        if args.command == 'probe':
            snapshot = asyncio.run(collect())
            missing = sum(b[k] is None for b in snapshot['buckets'] for k in ('primary', 'secondary'))
            print(f"真实额度读取成功：{len(snapshot['buckets'])} 个 bucket，{missing} 个缺失窗口；未输出账号或额度详情")
            return
        config = load_config(args.config)
        if args.command == 'pair':
            create_pairing(config, args.name, args.output)
        elif args.command == 'devices':
            print(json.dumps(api(config, 'GET', '/v1/devices'), ensure_ascii=False, indent=2))
        elif args.command == 'revoke':
            import uuid
            device_id = str(uuid.UUID(args.device_id))
            api(config, 'DELETE', '/v1/devices/' + device_id)
            print('设备凭据已撤销')
        else:
            # Lock spans both collection and upload; manual and launchd runs cannot race.
            lock_path = args.config.parent / 'collector.lock'
            with open(lock_path, 'a') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise VibeWatchError('已有采集器运行，请先停止它') from None
                state_path = args.config.parent / 'state.json'
                while True:
                    try:
                        run_once(config, state_path, force=args.command == 'once')
                    except (VibeWatchError, OSError, asyncio.TimeoutError, ValueError):
                        if args.command == 'once':
                            raise
                        print('采集或上传失败，将在下个采集周期重试；未更新心跳', file=sys.stderr, flush=True)
                    if args.command == 'once':
                        break
                    time.sleep(config['intervalSeconds'])
    except (VibeWatchError, OSError, asyncio.TimeoutError, ValueError, KeyError) as error:
        print(str(error) if isinstance(error, VibeWatchError) else '操作失败，请检查本机环境或配置（敏感错误内容已省略）', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
