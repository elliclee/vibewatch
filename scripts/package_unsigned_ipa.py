#!/usr/bin/env python3
"""Package a device archive for re-signing; never loads Apple credentials."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile


def package(archive: Path, output: Path):
    app = archive / 'Products/Applications/VibeWatch.app'
    bundles = [app, app / 'Watch/VibeWatchWatch.app',
               app / 'Watch/VibeWatchWatch.app/PlugIns/VibeWatchWidgets.appex',
               app / 'PlugIns/VibeWatchPhoneWidgets.appex']
    metadata = []
    for bundle, platform in zip(bundles, ['iPhoneOS', 'WatchOS', 'WatchOS', 'iPhoneOS']):
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        if info['CFBundleSupportedPlatforms'] != [platform]:
            raise ValueError(f'Not a device build: {bundle.name}')
        executable = bundle / info['CFBundleExecutable']
        build = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(executable)], text=True)
        if 'SIMULATOR' in build or not executable.stat().st_mode & 0o111:
            raise ValueError(f'Invalid device executable: {bundle.name}')
        metadata.append({
            'path': 'Payload/' + str(bundle.relative_to(app.parent)),
            'bundleId': info['CFBundleIdentifier'],
            'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
            'minimumOS': info['MinimumOSVersion'], 'platform': platform,
            'appGroup': info.get('VibeWatchAppGroup'),
            'keychainGroupBeforeResigning': info.get('VibeWatchKeychainGroup'),
        })
    watch_info = plistlib.loads((bundles[1] / 'Info.plist').read_bytes())
    if watch_info['WKCompanionAppBundleIdentifier'] != metadata[0]['bundleId']:
        raise ValueError('Watch companion bundle ID mismatch')
    if len({(m['version'], m['build']) for m in metadata}) != 1:
        raise ValueError('Embedded bundle versions differ')
    if list(app.rglob('embedded.mobileprovision')):
        raise ValueError('Expected archive without provisioning profiles')
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise FileExistsError(output)
    with tempfile.TemporaryDirectory(prefix='vibewatch-ipa-') as directory:
        payload = Path(directory) / 'Payload'
        payload.mkdir()
        shutil.copytree(app, payload / app.name, symlinks=True)
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(payload), str(output)], check=True)
    with zipfile.ZipFile(output) as ipa:
        if ipa.testzip() is not None:
            raise ValueError('IPA integrity check failed')
        for bundle in metadata:
            if bundle['path'] + '/Info.plist' not in ipa.namelist():
                raise ValueError('Embedded bundle missing from IPA')
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.ipa.sha256').write_text(f'{digest}  {output.name}\n')
    report = {'file': output.name, 'bytes': output.stat().st_size, 'sha256': digest,
              'requiresResigning': True, 'bundles': metadata}
    output.with_suffix('.manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.archive, args.output)
