#!/usr/bin/env python3
"""Prints the Nuvio version and the resolved AetherEngine package versions, one per line."""

import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
RESOLVED = ROOT / "iosApp" / "iosApp.xcodeproj" / "project.xcworkspace" / "xcshareddata" / "swiftpm" / "Package.resolved"
VERSION_FILE = ROOT / "iosApp" / "Configuration" / "Version.xcconfig"
NAMES = {
    "aetherengine": "AetherEngine",
    "ffmpegbuild": "FFmpegBuild (AetherEngine's FFmpeg)",
    "libdovi": "LibDovi",
    "libtruehd": "LibTrueHD",
}


def setting(name: str) -> str:
    match = re.search(rf"^\s*{name}\s*=\s*([^\s#]+)", VERSION_FILE.read_text(encoding="utf-8"), re.MULTILINE)
    return match.group(1) if match else "?"


def main() -> None:
    print(f"Nuvio {setting('MARKETING_VERSION')} ({setting('CURRENT_PROJECT_VERSION')})")
    if not RESOLVED.is_file():
        print("AetherEngine: not resolved")
        return
    pins = json.loads(RESOLVED.read_text(encoding="utf-8")).get("pins", [])
    for pin in pins:
        name = NAMES.get(pin.get("identity", ""))
        if not name:
            continue
        state = pin.get("state", {})
        version = state.get("version") or state.get("branch") or state.get("revision", "?")[:12]
        print(f"{name} {version}")


if __name__ == "__main__":
    main()
