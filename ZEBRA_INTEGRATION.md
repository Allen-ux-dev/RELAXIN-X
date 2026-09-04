# Relaxin Zebra Package Manager Patch

Target: `OwnGoalStudio/Relaxin` main snapshot inspected on 2026-09-02.

## What this patch changes

- Adds a **Package Managers** submenu under Advanced Options.
- Keeps **Sileo** selected by default and marks it Recommended.
- Adds **Zebra** as an Experimental option.
- Supports Sileo-only, Zebra-only, or both; the final selected manager cannot be turned off.
- Does **not** vendor Zebra into `Vendor/`, avoiding Relaxin's GPL-family license gate.
- When Zebra is selected, Relaxin fetches RootHide's `Packages` index before the engine starts.
- Selects the newest `xyz.willy.zebra` package for `iphoneos-arm64e`.
- Rejects malformed metadata, path traversal, oversized packages, non-HTTPS package URLs, size mismatches, and SHA-256 mismatches.
- Caches the verified `.deb` under the app cache directory and marks it read-only.
- Passes only that verified app-container path into the bootstrap finalization stage.
- Preserves the existing Sileo install path and RootHide bootstrap logic.
- Does not modify exploit, kernel-access, basebin, or RootHide bootstrap download code.

## Apply

From the root of a clean Relaxin checkout:

```bash
python3 /path/to/Relaxin-zebra-patch/apply_relaxin_zebra.py
```

The first command is a dry-run. If it reports `Patch preflight passed`, apply it:

```bash
python3 /path/to/Relaxin-zebra-patch/apply_relaxin_zebra.py --apply
```

The patcher creates `.relaxin-zebra-backup/` before modifying existing files.

## Restore

```bash
python3 /path/to/Relaxin-zebra-patch/apply_relaxin_zebra.py --restore
```

## Verify on macOS

Run Relaxin's normal checks after applying:

```bash
make format-lint
make check
make test-host
make build
```

Then package only after the build succeeds:

```bash
make ipa
```

## Local verification already performed

In the available Linux environment, the following were verified:

- TDD red state: core tests failed before the new selection/index types existed.
- Core tests pass after implementation.
- Patch dry-run uniquely matches all intended source contexts in a source fixture.
- Patch apply succeeds and creates backups.
- Patch restore returns the fixture to its prior state and removes newly added files.
- Re-apply after restore succeeds.
- `apply_relaxin_zebra.py` passes Python bytecode compilation.

The Linux environment has Swift 6.2.1 but no Xcode/iOS SDK, so an actual Relaxin iOS build was **not** claimed or performed here.

## Scope note

This bundle implements package-manager selection and Zebra installation during the jailbreak/bootstrap flow. The existing post-jailbreak **Reinstall Sileo** maintenance action has not yet been generalized into a full Sileo/Zebra maintenance screen; that is intentionally left as the next isolated change rather than widening the engine action API in the same patch.
