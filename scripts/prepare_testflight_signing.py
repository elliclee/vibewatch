#!/usr/bin/env python3
"""复用匹配本地私钥的分发证书，生成 VibeWatch 专用描述文件及导出选项。

先在开发者门户关联 Watch / Widget 的 App Group，再运行本脚本。
不输出签名材料，不修改其他应用，不创建或撤销证书。
"""
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TEAM = os.environ.get("VIBEWATCH_TEAM_ID", "")
PREFIX = os.environ.get("VIBEWATCH_BUNDLE_PREFIX", "dev.vibewatch")
GROUP = os.environ.get("VIBEWATCH_APP_GROUP", f"group.{PREFIX}.shared")
BUNDLES = [f"{PREFIX}.{suffix}" for suffix in ["phone", "phone.watch", "phone.watch.widgets"]]
OUT = ROOT / "artifacts/testflight"


def asc(*args):
    result = subprocess.run(["bash", str(ROOT / "scripts/asc.sh"), *args],
                            capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(f"asc {' '.join(args[:3])} failed: {result.stderr[:1500]}")
    return json.loads(result.stdout) if result.stdout.strip() else {}


def decode_profile(content):
    raw = base64.b64decode(content)
    with tempfile.NamedTemporaryFile(suffix=".mobileprovision") as f:
        f.write(raw); f.flush()
        decoded = subprocess.run(["security", "cms", "-D", "-i", f.name],
                                 capture_output=True, check=True).stdout
    return raw, plistlib.loads(decoded)


def valid_profile(payload, bundle, fingerprint):
    ent = payload.get("Entitlements", {})
    return (payload.get("ExpirationDate", dt.datetime.min) > dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
            and payload.get("TeamIdentifier") == [TEAM]
            and ent.get("application-identifier") == f"{TEAM}.{bundle}"
            and not ent.get("get-task-allow", False)
            and "ProvisionedDevices" not in payload
            and not payload.get("ProvisionsAllDevices", False)
            and any(hashlib.sha1(c).hexdigest().upper() == fingerprint for c in payload.get("DeveloperCertificates", []))
            and (
                (bundle == BUNDLES[0] or GROUP in ent.get("com.apple.security.application-groups", []))
                and f"{TEAM}.*" in ent.get("keychain-access-groups", [])))


def main():
    if not TEAM:
        raise RuntimeError("Set VIBEWATCH_TEAM_ID to your Apple Developer team ID")
    OUT.mkdir(parents=True, exist_ok=True)
    identities = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                                capture_output=True, text=True, check=True).stdout
    fingerprints = {m.group(1) for line in identities.splitlines()
                    if "Apple Distribution" in line and f"({TEAM})" in line
                    if (m := re.search(r"\b([A-F0-9]{40})\b", line))}
    certs = asc("certificates", "list", "--certificate-type", "DISTRIBUTION", "--paginate")["data"]
    matched = [(c, hashlib.sha1(base64.b64decode(c["attributes"]["certificateContent"])).hexdigest().upper()) for c in certs]
    matched = [(c, fingerprint) for c, fingerprint in matched if fingerprint in fingerprints]
    if not matched:
        raise RuntimeError("No remote distribution certificate matches this team's local signing identity")
    cert, fingerprint = matched[0]
    print("Matched remote distribution certificate to local signing identity.", flush=True)
    remote = asc("bundle-ids", "list", "--identifier", ",".join(BUNDLES), "--paginate")["data"]
    ids = {b["attributes"]["identifier"]: b["id"] for b in remote if b["attributes"].get("seedId") == TEAM}
    profiles = asc("profiles", "list", "--profile-type", "IOS_APP_STORE", "--paginate")["data"]
    selected = {}
    for bundle, label in zip(BUNDLES, ["Phone", "Watch", "Widgets", "PhoneWidgets"]):
        prefix = f"VibeWatch {label} App Store"
        found = None
        for profile in profiles:
            attrs = profile["attributes"]
            if not attrs["name"].startswith(prefix) or attrs["profileState"] != "ACTIVE":
                continue
            raw, payload = decode_profile(attrs["profileContent"])
            if valid_profile(payload, bundle, fingerprint):
                found = raw, payload
                break
        if found is None:
            name = f"{prefix} {dt.datetime.now().strftime('%Y%m%d-%H%M%S')}"
            created = asc("profiles", "create", "--name", name, "--profile-type", "IOS_APP_STORE",
                          "--bundle", ids[bundle], "--certificate", cert["id"])["data"]
            found = decode_profile(created["attributes"]["profileContent"])
            if not valid_profile(found[1], bundle, fingerprint):
                raise RuntimeError(f"Profile for {bundle} lacks required distribution/shared-group permissions; complete portal association before retrying")
        raw, payload = found
        path = OUT / f"{label}.mobileprovision"
        path.write_bytes(raw); path.chmod(0o600)
        asc("profiles", "local", "install", "--path", str(path), "--force")
        selected[bundle] = payload["Name"]
        print(f"Installed verified {label} App Store profile.", flush=True)
    options = {"method": "app-store-connect", "destination": "export", "teamID": TEAM,
               "signingStyle": "manual", "signingCertificate": fingerprint,
               "provisioningProfiles": selected, "uploadSymbols": True,
               "manageAppVersionAndBuildNumber": False}
    (OUT / "ExportOptions.plist").write_bytes(plistlib.dumps(options))
    (OUT / "signing.json").write_text(json.dumps({"team": TEAM, "bundlePrefix": PREFIX, "appGroup": GROUP, "identity": fingerprint, "profiles": selected}, indent=2))
    print("Prepared signing.json and ExportOptions.plist in ignored artifacts/testflight/.")


if __name__ == "__main__":
    main()
