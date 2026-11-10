#!/usr/bin/env python3
"""Compile the production native tab controller and run its checks on iOS Simulator."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile


def run(*args, **kwargs):
    return subprocess.run(args, text=True, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="SceneDelegate.swift to check (defaults to production)")
    parser.add_argument("--device", help="Booted simulator UDID")
    parser.add_argument("--baseline", action="store_true", help="Skip the pre-fix negative-index trap")
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = (options.source or root / "ios/Runner/SceneDelegate.swift").resolve()
    framework = root / "build/ios/Debug-iphonesimulator/Flutter.framework"
    if not framework.is_dir():
        sys.exit("Build the Flutter iOS simulator app first to provide Flutter.framework.")
    device = options.device
    if not device:
        devices = json.loads(run("xcrun", "simctl", "list", "devices", "booted", "--json", capture_output=True).stdout)
        device = next((item["udid"] for group in devices["devices"].values() for item in group if item["state"] == "Booted"), None)
    if not device:
        sys.exit("Boot an iOS 26+ simulator before running these checks.")
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path", capture_output=True).stdout.strip()
    arch = os.uname().machine
    bundle_id = "com.example.piliplus.native-tab-checks"
    with tempfile.TemporaryDirectory(prefix="piliplus-native-tabs-") as temporary:
        app = Path(temporary) / "NativeTabChecks.app"
        app.mkdir()
        (app / "Frameworks").mkdir()
        (app / "flutter_assets").mkdir()
        shutil.copytree(framework, app / "Frameworks/Flutter.framework")
        run("xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-sdk", sdk,
            "-target", f"{arch}-apple-ios26.0-simulator", "-F", str(framework.parent),
            "-framework", "Flutter", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
            str(source), str(root / "test/native/native_tab_selection_checks.swift"),
            "-o", str(app / "NativeTabChecks"))
        with (app / "Info.plist").open("wb") as stream:
            plistlib.dump({
                "CFBundleIdentifier": bundle_id,
                "CFBundleExecutable": "NativeTabChecks",
                "CFBundleName": "NativeTabChecks",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0",
                "MinimumOSVersion": "26.0",
                "UIDeviceFamily": [1, 2],
                "LSRequiresIPhoneOS": True,
                "UILaunchScreen": {},
                "UIApplicationSceneManifest": {
                    "UIApplicationSupportsMultipleScenes": False,
                    "UISceneConfigurations": {
                        "UIWindowSceneSessionRoleApplication": [{
                            "UISceneConfigurationName": "Checks",
                            "UISceneDelegateClassName": "NativeTabChecksSceneDelegate",
                        }],
                    },
                },
            }, stream)
        run("codesign", "--force", "--deep", "--sign", "-", str(app), capture_output=True)
        run("xcrun", "simctl", "install", device, str(app), capture_output=True)
        arguments = ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device, bundle_id]
        if options.baseline:
            arguments.append("--baseline")
        try:
            launched = subprocess.run(arguments, text=True, capture_output=True, timeout=45)
        finally:
            subprocess.run(["xcrun", "simctl", "uninstall", device, bundle_id], text=True, capture_output=True)
        prefix = "PILIPLUS_NATIVE_TAB_CHECKS="
        lines = (launched.stdout + launched.stderr).splitlines()
        results = next((line.split(prefix, 1)[1] for line in lines if prefix in line), None)
        if results is None:
            print(launched.stdout + launched.stderr)
            sys.exit("The native probe exited before reporting its checks.")
        result = json.loads(results)
        for name in result["passed"]:
            print(f"PASS {name}")
        for failure in result["failed"]:
            print(f"FAIL {failure['name']}: {failure['error']}")
        print(f"{len(result['passed'])} passed; {len(result['failed'])} failed")
        sys.exit(bool(result["failed"]))


if __name__ == "__main__":
    main()
