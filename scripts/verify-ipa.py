"""Check the delivered archive against the project resources and expected build."""
import hashlib
import json
from pathlib import Path
import plistlib
import sys
import zipfile


archive = Path(sys.argv[1])
expected_build = sys.argv[2]
resources = Path(__file__).resolve().parents[1] / "Jiuzhou" / "AndroidArt"
with zipfile.ZipFile(archive) as package:
    assert package.testzip() is None, "Corrupt ZIP entry"
    root = "Payload/Jiuzhou.app/"
    info = plistlib.loads(package.read(root + "Info.plist"))
    assert info["CFBundleVersion"] == expected_build, info["CFBundleVersion"]
    assert info["CFBundleShortVersionString"] == "0.1.0"
    assert info["CFBundleIdentifier"] == "app.vanilla7419.emerald5335"
    assert info["UIAppFonts"] == ["NotoSansCJK-Regular.ttc"]
    assert info["NSAppTransportSecurity"]["NSAllowsArbitraryLoads"] is True
    assert info.get("NSMicrophoneUsageDescription")
    names = set(package.namelist())
    images = [p.name for p in resources.iterdir() if p.suffix.lower() in (".png", ".jpeg", ".jpg")]
    for name in images + ["NotoSansCJK-Regular.ttc", "OpenCORE-AMR-LICENSE.txt"]:
        assert root + name in names, "Missing resource: " + name
    assert root + "embedded.mobileprovision" not in names, "Unexpected provisioning profile"
    executable = package.read(root + info["CFBundleExecutable"])
    assert executable[:4] == b"\xcf\xfa\xed\xfe", "Expected 64-bit Mach-O"
    print(json.dumps({
        "file": str(archive.resolve()),
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "bundle_id": info["CFBundleIdentifier"],
        "images_present": len(images),
        "zip_integrity": "passed",
        "bytes": archive.stat().st_size,
        "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
    }, ensure_ascii=False, indent=2))
