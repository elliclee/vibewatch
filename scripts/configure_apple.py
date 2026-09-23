#!/usr/bin/env python3
"""生成 gitignored XcodeGen 配置，不写入证书或修改默认工程。"""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def render(spec, prefix, team):
    if not re.fullmatch(r'[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+', prefix):
        raise ValueError('Bundle 前缀需要使用反向域名格式，例如 com.example.vibewatch')
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Team ID 必须为 10 位大写字母或数字')
    return (spec.replace('VIBEWATCH_BUNDLE_PREFIX: dev.vibewatch', f'VIBEWATCH_BUNDLE_PREFIX: {prefix}')
            .replace('VIBEWATCH_APP_GROUP: group.dev.vibewatch.shared', f'VIBEWATCH_APP_GROUP: group.{prefix}.shared')
            .replace('VIBEWATCH_KEYCHAIN_GROUP: $(AppIdentifierPrefix)dev.vibewatch.shared',
                     f'VIBEWATCH_KEYCHAIN_GROUP: $(AppIdentifierPrefix){prefix}.shared')
            .replace('CODE_SIGN_STYLE: Automatic', f'CODE_SIGN_STYLE: Automatic\n    DEVELOPMENT_TEAM: {team}'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', required=True)
    parser.add_argument('--team', required=True)
    args = parser.parse_args()
    try:
        value = render((ROOT / 'apple/project.yml').read_text(), args.prefix, args.team)
    except ValueError as error:
        parser.error(str(error))
    output = ROOT / 'apple/project.local.yml'
    output.write_text(value)
    print('已生成 apple/project.local.yml；执行 xcodegen generate --spec apple/project.local.yml')


if __name__ == '__main__':
    main()
