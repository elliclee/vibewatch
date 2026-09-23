#!/usr/bin/env python3
"""生成并验证签名 IPA；只有显式 --upload 才上传 TestFlight。

先运行 prepare_testflight_signing.py。日志和签名产物只写入 artifacts/。
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/testflight"


def run_logged(args, name):
    with (OUT / f"{name}.log").open("w") as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"{name} failed; inspect {OUT / (name + '.log')}")
    print(f"{name} completed.", flush=True)


def verify_app(app, signing):
    apps = [app, app / "Watch/VibeWatchWatch.app",
            app / "Watch/VibeWatchWatch.app/PlugIns/VibeWatchWidgets.appex"]
    prefix = signing["bundlePrefix"]
    expected = [f"{prefix}.{suffix}" for suffix in ["phone", "phone.watch", "phone.watch.widgets"]]
    if (app / "PlugIns/VibeWatchPhoneWidgets.appex").exists():
        raise RuntimeError("Phone widget must not be embedded in this release")
    version = None
    for path, bundle in zip(apps, expected):
        info = plistlib.loads((path / "Info.plist").read_bytes())
        privacy = plistlib.loads((path / "PrivacyInfo.xcprivacy").read_bytes())
        reason = "CA92.1" if bundle == expected[0] else "1C8F.1"
        if not any(item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults"
                   and reason in item.get("NSPrivacyAccessedAPITypeReasons", [])
                   for item in privacy.get("NSPrivacyAccessedAPITypes", [])):
            raise RuntimeError(f"Missing UserDefaults reason for {bundle}")
        if info["CFBundleIdentifier"] != bundle:
            raise RuntimeError(f"Unexpected bundle identifier for {path.name}")
        actual_version = (info["CFBundleShortVersionString"], info["CFBundleVersion"])
        version = version or actual_version
        if actual_version != version:
            raise RuntimeError("Nested versions differ")
        subprocess.run(["codesign", "--verify", "--strict", str(path)], capture_output=True, check=True)
        signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(path)],
                                capture_output=True, check=True)
        ent = plistlib.loads(signed.stdout)
        if ent.get("application-identifier") != f"{signing['team']}.{bundle}" or ent.get("get-task-allow", False):
            raise RuntimeError(f"Unexpected signing entitlements for {bundle}")
        profile = subprocess.run(["security", "cms", "-D", "-i", str(path / "embedded.mobileprovision")],
                                 capture_output=True, check=True)
        payload = plistlib.loads(profile.stdout)
        if payload["TeamIdentifier"] != [signing["team"]] or "ProvisionedDevices" in payload:
            raise RuntimeError(f"Unexpected distribution profile for {bundle}")
        if bundle == expected[0]:
            if ent.get("com.apple.security.application-groups") or not info.get("VibeWatchPrivatePhoneStorage"):
                raise RuntimeError("Phone must retain private storage in this release")
            if f"{signing['team']}.{bundle}" not in ent.get("keychain-access-groups", []):
                raise RuntimeError("Phone legacy Keychain group missing")
        group = signing["appGroup"]
        shared_keychain = f"{signing['team']}.{prefix}.shared"
        if bundle != expected[0] and (group not in ent.get("com.apple.security.application-groups", []) or shared_keychain not in ent.get("keychain-access-groups", [])):
            raise RuntimeError(f"Missing signed shared groups for {bundle}")
        if bundle != expected[0] and group not in payload["Entitlements"].get("com.apple.security.application-groups", []):
            raise RuntimeError(f"Profile does not permit shared group for {bundle}")
        if bundle == expected[1] and info.get("WKCompanionAppBundleIdentifier") != expected[0]:
            raise RuntimeError("Watch companion identifier mismatch")
        print(f"Verified signed {bundle} ({actual_version[0]} / {actual_version[1]}).", flush=True)
    return version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upload", action="store_true")
    args = parser.parse_args()
    if args.upload and not os.environ.get("ASC_APP_ID"):
        parser.error("--upload requires your own ASC_APP_ID")
    signing = json.loads((OUT / "signing.json").read_text())
    run_logged(["xcodegen", "generate", "--spec", "apple/project.yml"], "xcodegen")
    archive = OUT / "VibeWatch.xcarchive"
    ipa = OUT / "VibeWatch.ipa"
    cmd = ["bash", str(ROOT / "scripts/asc.sh"), "xcode", "archive", "--project", "apple/VibeWatch.xcodeproj",
           "--scheme", "VibeWatch", "--configuration", "Release", "--archive-path", str(archive), "--overwrite"]
    flags = ["-destination", "generic/platform=iOS", "CODE_SIGN_STYLE=Manual",
             f"DEVELOPMENT_TEAM={signing['team']}", f"CODE_SIGN_IDENTITY={signing['identity']}",
             f"VIBEWATCH_BUNDLE_PREFIX={signing['bundlePrefix']}",
             f"VIBEWATCH_APP_GROUP={signing['appGroup']}",
             f"VIBEWATCH_KEYCHAIN_GROUP=$(AppIdentifierPrefix){signing['bundlePrefix']}.shared"]
    for bundle, key in zip([f"{signing['bundlePrefix']}.{suffix}" for suffix in ["phone", "phone.watch", "phone.watch.widgets"]],
                           ["PHONE", "WATCH", "WIDGET"]):
        flags.append(f"VIBEWATCH_{key}_PROFILE={signing['profiles'][bundle]}")
    run_logged(cmd + [f"--xcodebuild-flag={flag}" for flag in flags], "archive")
    verify_app(archive / "Products/Applications/VibeWatch.app", signing)
    run_logged(["bash", str(ROOT / "scripts/asc.sh"), "xcode", "export", "--archive-path", str(archive),
                "--ipa-path", str(ipa), "--export-options", str(OUT / "ExportOptions.plist"), "--overwrite"], "export")
    with tempfile.TemporaryDirectory() as directory:
        with zipfile.ZipFile(ipa) as zipped:
            zipped.extractall(directory)
        version = verify_app(Path(directory) / "Payload/VibeWatch.app", signing)
    (OUT / "verified-build.json").write_text(json.dumps({"version": version[0], "build": version[1],
        "bundles": 3, "ipa": str(ipa)}, indent=2))
    if args.upload:
        run_logged(["bash", str(ROOT / "scripts/asc.sh"), "builds", "upload", "--app", os.environ["ASC_APP_ID"],
                    "--ipa", str(ipa)], "upload")
    else:
        print("Signed IPA verified; no upload requested.")


if __name__ == "__main__":
    main()
