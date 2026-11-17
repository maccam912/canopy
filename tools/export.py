#!/usr/bin/env python3
"""Export one platform and package a distributable file with a checksum."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
from bootstrap import ROOT, VERSIONS, templates
from godot import run

PRESETS = {"linux": ("Linux", "canopy.x86_64"), "windows": ("Windows", "canopy.exe"),
           "macos": ("macOS", "canopy.zip"), "android": ("Android", "canopy.apk")}
HOST = {"darwin": "macos", "linux": "linux", "win32": "windows"}[sys.platform]


def smoke(command):
    """The shipped build must boot and grow a forest for a few seconds."""
    result = subprocess.run([str(part) for part in command] + ["--headless", "--", "--smoke"],
                            capture_output=True, text=True, timeout=120)
    text = result.stdout + result.stderr
    if result.returncode or "ERROR:" in text or "CANOPY_SMOKE_PASS" not in text:
        raise RuntimeError(text)


def export(platform):
    if platform not in (HOST, "android"):
        raise RuntimeError("Export on the native platform; Android can export from any desktop")
    templates()
    if platform == "android":
        from android import prepare
        _, _, key = prepare()
        # A release build signed with the development key: fine for
        # sideloading, not a store identity.
        os.environ["GODOT_ANDROID_KEYSTORE_RELEASE_PATH"] = str(key)
        os.environ["GODOT_ANDROID_KEYSTORE_RELEASE_USER"] = "androiddebugkey"
        os.environ["GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"] = "android"
    run(["--headless", "--editor", "--import"], timeout=300)
    preset, name = PRESETS[platform]
    destination = ROOT / "build" / platform
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    output = destination / name
    run(["--headless", "--export-release", preset, str(output)], timeout=900)
    if not output.exists() or output.stat().st_size == 0:
        raise RuntimeError("Godot did not produce " + str(output))
    if platform == "android":
        sdk = Path(os.environ["ANDROID_HOME"])
        signer = sdk / "build-tools" / VERSIONS["android"]["build_tools"] / ("apksigner.bat" if os.name == "nt" else "apksigner")
        subprocess.run([str(signer), "verify", "--verbose", str(output)], check=True)
        with zipfile.ZipFile(output) as archive:
            if not any(entry.startswith("lib/arm64-v8a/") for entry in archive.namelist()):
                raise RuntimeError("APK is missing the ARM64 engine")
    if platform == "macos":
        verification = ROOT / "build/macos-verify"
        if verification.exists():
            shutil.rmtree(verification)
        subprocess.run(["ditto", "-x", "-k", str(output), str(verification)], check=True)
        apps = list(verification.glob("*.app"))
        if len(apps) != 1:
            raise RuntimeError("Expected one macOS application")
        subprocess.run(["plutil", "-lint", str(apps[0] / "Contents/Info.plist")], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", "--all-architectures", str(apps[0])], check=True)
        smoke([next((apps[0] / "Contents/MacOS").iterdir())])
    if platform in ("linux", "windows"):
        output.chmod(output.stat().st_mode | 0o111)
        smoke([output])
    release = ROOT / "build/artifacts"
    release.mkdir(parents=True, exist_ok=True)
    artifact = release / ("canopy-" + platform + (".apk" if platform == "android" else ".zip"))
    if platform in ("macos", "android"):
        shutil.copyfile(output, artifact)
    else:
        with zipfile.ZipFile(artifact, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in destination.rglob("*"):
                if path.is_file():
                    archive.write(path, path.relative_to(destination))
    checksum = hashlib.sha256(artifact.read_bytes()).hexdigest()
    artifact.with_suffix(artifact.suffix + ".sha256").write_text(checksum + "  " + artifact.name + "\n")
    print(artifact)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=list(PRESETS))
    export(parser.parse_args().platform)
