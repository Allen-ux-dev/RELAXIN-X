#!/usr/bin/env python3
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SCRIPT = ROOT / "DevKit/Helpers/UpstreamBaseline/inspect-upstream-release.py"
sys.path.insert(0, str(HERE / "fixtures"))
from build_fixture import build_fixture


def run() -> None:
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        ipa = temp / "Relaxin-test.ipa"
        expected = build_fixture(ipa)
        output = temp / "out"
        subprocess.run(
            [sys.executable, str(SCRIPT), str(ipa), "--output", str(output)],
            cwd=ROOT,
            check=True,
        )
        report = json.loads((output / "report.json").read_text())
        candidate = plistlib.loads((output / "candidate-baseline.plist").read_bytes())

        assert report["release"]["version"] == "9.9.9-test"
        assert report["release"]["sha256"] == expected["release_sha256"]
        assert report["kernelOffsets"]["profileCount"] == 2
        assert report["kernelOffsets"]["indexCount"] == 2
        assert report["kernelOffsets"]["sptmTxmMetadataProfileCount"] == 1
        assert report["kernelOffsets"]["generatedAt"] == "2026-09-03T12:00:00+00:00"
        assert report["resources"]["basebin.tar"]["sha256"] == expected["basebin.tar"]
        assert report["resources"]["bootstrap_1900.tar.zst"]["sha256"] == expected["bootstrap_1900.tar.zst"]
        assert report["classifications"]["engine"] == "binary_changed_source_delta_unknown"
        assert report["classifications"]["scope"] == "unsupported_scope_change"
        assert candidate["upstreamVersion"] == "9.9.9-test"
        assert candidate["releaseSHA256"] == expected["release_sha256"]
        assert candidate["autoPromote"] is False
        assert candidate["manifestSchema"] == 1
        assert candidate["kernelOffsetGeneration"] == "2026-09-03T12:00:00+00:00"

    print("ok upstream-baseline-inspector")


if __name__ == "__main__":
    run()
