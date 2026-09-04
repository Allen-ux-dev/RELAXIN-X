#!/usr/bin/env python3
"""Read-only Relaxin IPA/TIPA baseline inspector.

The inspector never executes binaries and never promotes a candidate baseline.
It only reads ZIP/plist/resource bytes and emits deterministic metadata.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

KNOWN_PRODUCTION_VERSION = "0.5.0"
KNOWN_SUPPORTED_BUILDS = {
    "20F75", "20G75", "20G81", "20H19", "20H30", "20H115",
    "21A329", "21A331", "21A340", "21A350", "21A351", "21A360",
    "21B74", "21B80", "21B91", "21B101", "21C62", "21C66",
    "21D50", "21D61",
}
RESOURCE_NAMES = (
    "KernelOffsets.plist",
    "basebin.tar",
    "bootstrap_1900.tar.zst",
    "sileo.deb",
    "roothideapp.deb",
)
ENGINE_SUFFIX = "RelaxinEngine.framework/RelaxinEngine"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_zip_members(archive: zipfile.ZipFile) -> None:
    for info in archive.infolist():
        path = PurePosixPath(info.filename)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError(f"unsafe archive entry: {info.filename}")


def find_app_prefix(names: list[str]) -> str:
    candidates: list[str] = []
    for name in names:
        parts = PurePosixPath(name).parts
        if len(parts) == 3 and parts[0] == "Payload" and parts[1].endswith(".app") and parts[2] == "Info.plist":
            candidates.append("/".join(parts[:2]) + "/")
    if len(candidates) != 1:
        raise ValueError(f"expected exactly one Payload/*.app/Info.plist, found {len(candidates)}")
    return candidates[0]


def read_plist(archive: zipfile.ZipFile, path: str) -> dict[str, Any]:
    try:
        value = plistlib.loads(archive.read(path))
    except KeyError as exc:
        raise ValueError(f"missing required plist: {path}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"plist root is not a dictionary: {path}")
    return value


def summarize_kernel_offsets(offsets: dict[str, Any]) -> dict[str, Any]:
    profiles = offsets.get("profiles")
    index = offsets.get("index")
    if not isinstance(profiles, list) or not isinstance(index, dict):
        raise ValueError("KernelOffsets.plist must contain profiles[] and index{}")

    sptm_txm_count = 0
    for profile in profiles:
        if not isinstance(profile, dict):
            raise ValueError("KernelOffsets profile is not a dictionary")
        sptm = profile.get("sptmSHA256")
        txm = profile.get("txmSHA256")
        if (sptm is None) != (txm is None):
            raise ValueError("SPTM/TXM digest metadata must be paired")
        if sptm is not None:
            if not isinstance(sptm, str) or not SHA256_RE.fullmatch(sptm):
                raise ValueError("invalid sptmSHA256 metadata")
            if not isinstance(txm, str) or not SHA256_RE.fullmatch(txm):
                raise ValueError("invalid txmSHA256 metadata")
            sptm_txm_count += 1

    for key, profile_index in index.items():
        if not isinstance(key, str) or not isinstance(profile_index, int):
            raise ValueError("KernelOffsets index has invalid entry types")
        if profile_index < 0 or profile_index >= len(profiles):
            raise ValueError(f"KernelOffsets index points outside profiles: {key}")

    builds = sorted({key.rsplit("|", 1)[-1] for key in index if "|" in key})
    products = sorted({key.split("|", 1)[0] for key in index if "|" in key})
    return {
        "schema": offsets.get("schema"),
        "profileVersion": offsets.get("profileVersion"),
        "generatedAt": offsets.get("generatedAt"),
        "source": offsets.get("source"),
        "profileCount": len(profiles),
        "indexCount": len(index),
        "sptmTxmMetadataProfileCount": sptm_txm_count,
        "builds": builds,
        "productCount": len(products),
        "products": products,
    }


def inspect_release(path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    if not path.is_file():
        raise ValueError(f"release file does not exist: {path}")
    release_hash = sha256_file(path)

    try:
        archive = zipfile.ZipFile(path)
    except zipfile.BadZipFile as exc:
        raise ValueError("release is not a valid IPA/TIPA ZIP archive") from exc

    with archive:
        validate_zip_members(archive)
        names = archive.namelist()
        app_prefix = find_app_prefix(names)
        info = read_plist(archive, app_prefix + "Info.plist")
        offsets_path = app_prefix + "KernelOffsets.plist"
        offsets = read_plist(archive, offsets_path)
        offset_summary = summarize_kernel_offsets(offsets)

        resources: dict[str, Any] = {}
        for resource_name in RESOURCE_NAMES:
            member = app_prefix + resource_name
            if member not in names:
                resources[resource_name] = {"present": False}
                continue
            data = archive.read(member)
            resources[resource_name] = {
                "present": True,
                "size": len(data),
                "sha256": sha256_bytes(data),
            }

        engine_member = app_prefix + ENGINE_SUFFIX
        engine = {"present": engine_member in names}
        if engine["present"]:
            engine_data = archive.read(engine_member)
            engine.update(size=len(engine_data), sha256=sha256_bytes(engine_data))

    version = str(info.get("CFBundleShortVersionString", "unknown"))
    builds = set(offset_summary["builds"])
    scope_is_verified_050 = version == KNOWN_PRODUCTION_VERSION and builds.issubset(KNOWN_SUPPORTED_BUILDS)

    report: dict[str, Any] = {
        "toolSchema": 1,
        "readOnly": True,
        "autoPromote": False,
        "release": {
            "path": path.name,
            "sha256": release_hash,
            "version": version,
            "build": str(info.get("CFBundleVersion", "unknown")),
            "bundleIdentifier": info.get("CFBundleIdentifier"),
            "minimumOSVersion": info.get("MinimumOSVersion"),
        },
        "kernelOffsets": offset_summary,
        "resources": resources,
        "engine": engine,
        "classifications": {
            "engine": "binary_changed_source_delta_unknown" if engine["present"] else "unchanged",
            "kernelOffsets": "new_metadata" if offset_summary["sptmTxmMetadataProfileCount"] else "resource_changed",
            "scope": "unchanged" if scope_is_verified_050 else "unsupported_scope_change",
        },
        "warnings": [],
    }
    if not scope_is_verified_050:
        report["warnings"].append(
            "Observed OS/device scope is not auto-promoted; review source-backed backend/profile support first."
        )

    def resource_hash(name: str) -> str:
        value = resources.get(name, {})
        return str(value.get("sha256", "")) if value.get("present") else ""

    candidate: dict[str, Any] = {
        "manifestSchema": 1,
        "autoPromote": False,
        "id": f"candidate.relaxin.v{version}.{str(offset_summary.get('generatedAt', 'unknown'))[:10].replace('-', '')}",
        "upstreamProduct": "Relaxin",
        "upstreamVersion": version,
        "releaseSHA256": release_hash,
        "kernelOffsetGeneration": str(offset_summary.get("generatedAt", "unknown")),
        "kernelOffsetSHA256": resource_hash("KernelOffsets.plist"),
        "bootstrapGeneration": "1900" if resources.get("bootstrap_1900.tar.zst", {}).get("present") else "unknown",
        "bootstrapSHA256": resource_hash("bootstrap_1900.tar.zst"),
        "baseBinGeneration": "unknown",
        "baseBinSHA256": resource_hash("basebin.tar"),
        "minimumOSVersion": info.get("MinimumOSVersion", "unknown"),
        "observedBuilds": offset_summary["builds"],
        "observedProducts": offset_summary["products"],
        "promotionStatus": "review_required",
    }
    return report, candidate


def write_outputs(report: dict[str, Any], candidate: dict[str, Any], output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    (output / "report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (output / "candidate-baseline.plist").write_bytes(
        plistlib.dumps(candidate, fmt=plistlib.FMT_XML, sort_keys=True)
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Inspect a local Relaxin IPA/TIPA without executing bundled code.")
    parser.add_argument("release", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        report, candidate = inspect_release(args.release)
        write_outputs(report, candidate, args.output)
    except (OSError, ValueError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(f"wrote {args.output / 'report.json'}")
    print(f"wrote {args.output / 'candidate-baseline.plist'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
