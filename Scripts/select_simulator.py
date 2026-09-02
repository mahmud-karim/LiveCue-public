#!/usr/bin/env python3
import json
import subprocess

result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"], check=True, capture_output=True, text=True)
candidates = [device for devices in json.loads(result.stdout)["devices"].values() for device in devices if device.get("isAvailable") and device.get("name", "").startswith("iPhone")]
if not candidates:
    raise SystemExit("No available iPhone simulator was found")
preferred = ["iPhone 17 Pro Max", "iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro Max", "iPhone 16 Pro", "iPhone 16"]
candidates.sort(key=lambda item: (preferred.index(item["name"]) if item["name"] in preferred else len(preferred), item["name"]))
print(candidates[0]["udid"])

