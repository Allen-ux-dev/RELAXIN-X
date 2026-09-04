#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def copy_archive_fixture(destination: Path) -> Path:
    archive_root = destination / "Relaxin-Source-Archive"
    for relative in (
        "DevKit/Helpers",
        "Vendor",
        "RelaxinEngine/KernelAccess",
        "Relaxin/Resources",
    ):
        source = ROOT / relative
        target = archive_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copy2(source, target)
    git_dir = archive_root / ".git"
    assert not git_dir.exists(), "archive fixture must not contain .git"
    return archive_root


def install_macos_mktemp_shim(bin_dir: Path) -> None:
    shim = bin_dir / "mktemp"
    shim.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        "if [[ ${1:-} == -d && ${2:-} == -t && -n ${3:-} ]]; then\n"
        "  /usr/bin/mktemp -d \"${TMPDIR:-/tmp}/${3}.XXXXXX\"\n"
        "else\n"
        "  exec /usr/bin/mktemp \"$@\"\n"
        "fi\n",
        encoding="utf-8",
    )
    shim.chmod(0o755)


def run_archive_case(parent: Path, label: str) -> None:
    archive_root = copy_archive_fixture(parent)
    fake_bin = parent / "bin"
    fake_bin.mkdir(exist_ok=True)
    install_macos_mktemp_shim(fake_bin)

    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
    env.setdefault("TERM", "dumb")
    script = archive_root / "DevKit/Helpers/scan-licenses.sh"
    result = subprocess.run(
        [str(script)],
        cwd=archive_root,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    combined = result.stdout + result.stderr
    if result.returncode != 0:
        raise AssertionError(
            f"{label}: license scan must work from a source archive without .git\n"
            f"exit={result.returncode}\n{combined}"
        )
    if "license discovery: source-archive" not in combined:
        raise AssertionError(
            f"{label}: archive mode must be explicit in build logs\n" + combined
        )
    output = archive_root / "Relaxin/Resources/Licenses.txt"
    if not output.is_file() or output.stat().st_size == 0:
        raise AssertionError(f"{label}: license scan did not produce Licenses.txt")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="relaxin-license-archive-test-") as temp:
        run_archive_case(Path(temp), "standalone archive")

    with tempfile.TemporaryDirectory(prefix="relaxin-license-parent-git-test-") as temp:
        parent = Path(temp)
        subprocess.run(
            ["git", "init", "-q", str(parent)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        run_archive_case(parent, "archive nested inside unrelated git repo")

    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    if "DevKit/Tests/LicenseScanSourceArchive/test_contract.py" not in makefile:
        raise AssertionError("make test-host must include LicenseScanSourceArchive")

    print("LicenseScanSourceArchive: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
