"""Export named XCTest screenshots with Xcode 15's xcresulttool interface."""
import json
from pathlib import Path
import subprocess
import sys


bundle, destination = sys.argv[1:3]
include_all = "--all" in sys.argv[3:]
output = Path(destination)
output.mkdir(parents=True, exist_ok=True)
visited = set()
exported = set()


def inspect(reference=None):
    command = ["xcrun", "xcresulttool", "get", "--path", bundle, "--format", "json"]
    if reference:
        if reference in visited:
            return
        visited.add(reference)
        command += ["--id", reference]
    walk(json.loads(subprocess.check_output(command)))


def walk(value):
    if isinstance(value, list):
        for child in value:
            walk(child)
    elif isinstance(value, dict):
        name = value.get("name", {}).get("_value", "")
        payload = value.get("payloadRef", {}).get("id", {}).get("_value")
        image_type = value.get("uniformTypeIdentifier", {}).get("_value", "")
        named = any(label in name for label in ("landscape-world", "common-to-inventory"))
        if payload and (named or include_all and image_type == "public.png") and payload not in exported:
            filename = ("landscape-world" if "landscape-world" in name else "common-to-inventory") if named else "failure-" + str(len(exported))
            subprocess.run(["xcrun", "xcresulttool", "export", "--type", "file", "--path", bundle,
                            "--id", payload, "--output-path", str(output / (filename + ".png"))], check=True)
            exported.add(payload)
        for key, child in value.items():
            if key in ("testsRef", "summaryRef"):
                reference = child.get("id", {}).get("_value")
                if reference:
                    inspect(reference)
            else:
                walk(child)


inspect()
print("Exported", len(exported), "named screenshots to", output)
