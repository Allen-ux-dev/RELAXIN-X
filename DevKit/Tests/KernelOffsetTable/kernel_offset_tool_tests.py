#!/usr/bin/env python3

import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
GENERATOR = ROOT / "DevKit/Helpers/KernelOffsets/build-offset-table.py"
AUDITOR = ROOT / "DevKit/Helpers/KernelOffsets/audit-offset-table.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class KernelOffsetToolTests(unittest.TestCase):
    def test_generator_does_not_replace_table_on_index_conflict(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            corpus = temporary / "corpus"
            corpus.mkdir()
            for name in ("first.kernelcache", "second.kernelcache"):
                (corpus / name).write_bytes(b"")

            entries = []
            for name, digest in (
                ("first.kernelcache", "1" * 64),
                ("second.kernelcache", "2" * 64),
            ):
                entries.append(
                    {
                        "version": "17.0",
                        "build": "21A1",
                        "arch": "arm64e",
                        "path": name,
                        "sha256": digest,
                        "devices": ["iPhone15,2"],
                    }
                )
            (corpus / "index.json").write_text(
                json.dumps({"kernelcaches": entries}),
                encoding="utf-8",
            )

            dump = {
                "profileVersion": 1,
                "isArm64e": True,
                "isSPTMDevice": False,
                "isFileset": True,
                "hasPPLTextSection": True,
                "hasGFXOffsets": False,
                "staticKernelBase": 0xFFFFFFF007004000,
                "sptmArgs": 0,
                "xnuVersionPacked": 1,
                "xnuBuild": "10002.0.0~1",
                "osVersion": "17.0",
                "symbols": {
                    "cpu_ttep": 1,
                    "gVirtBase": 2,
                    "gPhysBase": 3,
                    "gPhysSize": 4,
                    "ptov_table": 5,
                    "allproc": 6,
                    "vm_map_pmap": 7,
                    "arm_tt_l1_index_mask": 8,
                    "t1sz_boot": 9,
                    "kernel_el": 10,
                },
                "offsetSets": ["translation"],
                "offsetDictionary": {
                    "kernelConstant.T1SZ_BOOT": {
                        "type": "uint64",
                        "value": 25,
                    }
                },
            }
            tool = temporary / "fake-dumper.py"
            tool.write_text(
                "#!/usr/bin/env python3\n"
                "import json\n"
                f"print(json.dumps({dump!r}))\n",
                encoding="utf-8",
            )
            tool.chmod(0o755)

            output = temporary / "KernelOffsets.plist"
            original = b"known-good-table"
            output.write_bytes(original)
            result = subprocess.run(
                [
                    str(GENERATOR),
                    "--corpus",
                    str(corpus),
                    "--tool",
                    str(tool),
                    "--output",
                    str(output),
                    "--jobs",
                    "1",
                ],
                capture_output=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), original)
            self.assertIn("有两个不同的 profile", result.stderr.decode("utf-8"))

    def test_audit_skips_cross_device_clusters_without_platform_metadata(self):
        auditor = load_module("kernel_offset_auditor", AUDITOR)
        base = 0xFFFFFFF007004000

        def profile(offset: int):
            gfx = {key: offset for key in auditor.GFX_OFFSET_KEYS}
            gfx.update(
                {
                    key: base + 0x1000
                    for key in auditor.GFX_ADDRESS_KEYS
                }
            )
            return {"staticKernelBase": base, "gfx": gfx}

        entries = [
            ("iPhone12,1", "21A1", profile(0x10)),
            ("iPhone13,1", "21A1", profile(0x20)),
        ]
        findings = auditor.Findings()
        auditor.check_gfx_clusters(entries, {}, findings, False)
        self.assertEqual(findings.errors, [])

        classified = auditor.Findings()
        platforms = {"iPhone12,1": "t8101", "iPhone13,1": "t8101"}
        auditor.check_gfx_clusters(entries, platforms, classified, False)
        self.assertEqual(len(classified.errors), 1)


if __name__ == "__main__":
    unittest.main()
