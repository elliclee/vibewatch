#!/usr/bin/env python3
"""验证生产 HTTPS 真实采集、上传、临时配对、读取与撤销，不输出凭据。"""
import argparse
import asyncio
import json
from pathlib import Path
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'agent'))
from vibewatch import DEFAULT_CONFIG, USER_AGENT, NoRedirect, api, collect, load_config


def request(server, path, *, token=None, body=None):
    headers = {'Content-Type': 'application/json', 'User-Agent': USER_AGENT}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    value = urllib.request.Request(server + path, headers=headers,
        data=None if body is None else json.dumps(body).encode())
    with urllib.request.build_opener(NoRedirect()).open(value, timeout=20) as response:
        assert response.headers.get('Cache-Control') == 'no-store'
        return json.load(response)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    config = load_config(args.config)
    server = config['server']
    assert server.startswith('https://'), 'Production check requires HTTPS'
    assert request(server, '/health') == {'status': 'ok'}
    snapshot = asyncio.run(collect(config['codex']))
    api(config, 'PUT', '/v1/snapshot', snapshot)
    pairing = api(config, 'POST', '/v1/pairings', {'name': 'cloud verification (temporary)'})
    try:
        token = request(server, '/v1/pairings/redeem', body={'code': pairing['code']})['token']
        result = request(server, '/v1/snapshot', token=token)
        assert result['snapshot'] == snapshot, 'Snapshot did not round-trip'
        assert result['receivedAt'] >= snapshot['collectedAt'] - 60
        for invalid_token in [None, config['uploadToken']]:
            try:
                request(server, '/v1/snapshot', token=invalid_token)
                raise AssertionError('Read authentication accepted invalid role')
            except urllib.error.HTTPError as error:
                assert error.code == 401
        try:
            request(server, '/v1/pairings/redeem', body={'code': pairing['code']})
            raise AssertionError('One-time code was reused')
        except urllib.error.HTTPError as error:
            assert error.code == 410
    finally:
        api(config, 'DELETE', '/v1/devices/' + pairing['deviceId'])
    try:
        request(server, '/v1/snapshot', token=token)
        raise AssertionError('Revoked device still has access')
    except urllib.error.HTTPError as error:
        assert error.code == 401
    print('线上闭环通过：真实采集 → HTTPS 上传 → 一次性配对 → 内容一致 → 权限隔离 → 撤销生效；未输出凭据或额度。')


if __name__ == '__main__':
    main()
