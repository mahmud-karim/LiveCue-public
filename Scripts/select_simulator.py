#!/usr/bin/env python3
import json
import subprocess
import sys

result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"], check=True, capture_output=True, text=True)
candidates = []
for runtime, devices in json.loads(result.stdout)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split(".iOS-")[1].split("-"))
    # Xcode 26.3 ships the iOS 26.2 SDK. Avoid older first-boot runtimes
    # or future runtimes installed for a different Xcode on the same runner.
    if version > (26, 2):
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            candidates.append({**device, "runtime": runtime, "version": version})
if not candidates:
    raise SystemExit("No available iPhone simulator was found")
preferred = ["iPhone 17 Pro Max", "iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro Max", "iPhone 16 Pro", "iPhone 16"]
candidates.sort(key=lambda item: (tuple(-part for part in item["version"]), preferred.index(item["name"]) if item["name"] in preferred else len(preferred), item["name"]))
print(f"Selected {candidates[0]['name']} on {candidates[0]['runtime']}", file=sys.stderr)
print(candidates[0]["udid"])
