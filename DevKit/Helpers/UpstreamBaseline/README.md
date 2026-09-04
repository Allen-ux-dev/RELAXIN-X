# Upstream Baseline Inspector

`inspect-upstream-release.py` is a host-only, read-only helper for reviewing a local Relaxin IPA/TIPA before any RELAXIN-X baseline update.

It uses only the Python standard library. It reads ZIP/plist/resource bytes, validates archive paths, hashes resources, summarizes KernelOffsets coverage/metadata, and writes:

- `report.json`
- `candidate-baseline.plist`

It **does not execute, disassemble, or decompile bundled binaries**, does not use the network, and never auto-promotes observed OS/device scope to supported.

## Future upgrade workflow

```text
inspect
  → review report
  → compare candidate manifest with the compiled production baseline
  → explicitly promote reviewed resource/baseline data
  → run host tests
  → run the Mac Xcode/iPhoneOS build
```

Example:

```bash
python3 DevKit/Helpers/UpstreamBaseline/inspect-upstream-release.py \
  /path/to/Relaxin-v0.5.0.ipa \
  --output build/UpstreamBaseline/v0.5.0
```

Inspection is intentionally separate from promotion. A new chip, OS build, or engine binary is evidence for review, not automatic proof of execution support.
