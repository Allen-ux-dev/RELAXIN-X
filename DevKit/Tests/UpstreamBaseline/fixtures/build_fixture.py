#!/usr/bin/env python3
import hashlib
import plistlib
import zipfile
from pathlib import Path


def build_fixture(path: Path) -> dict[str, str]:
    path.parent.mkdir(parents=True, exist_ok=True)
    info = {
        "CFBundleIdentifier": "dev.owngoal.Relaxin",
        "CFBundleShortVersionString": "9.9.9-test",
        "CFBundleVersion": "42",
        "MinimumOSVersion": "16.5",
    }
    offsets = {
        "schema": 1,
        "profileVersion": 1,
        "generatedAt": "2026-09-03T12:00:00+00:00",
        "source": "synthetic",
        "profiles": [
            {"kernelcacheSHA256": "a" * 64},
            {"kernelcacheSHA256": "b" * 64, "sptmSHA256": "c" * 64, "txmSHA256": "d" * 64},
        ],
        "index": {
            "iPhone15,4|21A329": 0,
            "iPhone16,1|21D61": 1,
        },
    }
    resources = {
        "basebin.tar": b"synthetic-basebin-v2\n",
        "bootstrap_1900.tar.zst": b"synthetic-bootstrap\n",
        "sileo.deb": b"synthetic-sileo\n",
        "roothideapp.deb": b"synthetic-roothide\n",
        "RelaxinEngine.framework/RelaxinEngine": b"synthetic-engine-binary\n",
    }
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("Payload/Test.app/Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        archive.writestr("Payload/Test.app/KernelOffsets.plist", plistlib.dumps(offsets, fmt=plistlib.FMT_BINARY, sort_keys=True))
        for name, data in resources.items():
            archive.writestr(f"Payload/Test.app/{name}", data)

    return {
        "release_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        **{name: hashlib.sha256(data).hexdigest() for name, data in resources.items()},
    }
