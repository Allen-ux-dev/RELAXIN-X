#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "DevKit/Helpers/run-xcodebuild.sh"
MAKEFILE = ROOT / "Makefile"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def write_executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


def behavioral_streaming_test() -> None:
    with tempfile.TemporaryDirectory(prefix="relaxin-xcode-streaming-") as temp:
        temp_root = Path(temp)
        helpers = temp_root / "DevKit/Helpers"
        helpers.mkdir(parents=True)
        shutil.copy2(SCRIPT, helpers / "run-xcodebuild.sh")
        write_executable(temp_root / ".env.sh", "#!/usr/bin/env bash\n")

        for helper in (
            "check-tools.sh",
            "check-zstd-integration.sh",
            "check-credits-localization.sh",
            "check-engine-localization.sh",
        ):
            write_executable(helpers / helper, "#!/usr/bin/env bash\nexit 0\n")

        fake_bin = temp_root / "bin"
        fake_bin.mkdir()
        write_executable(
            fake_bin / "xcodebuild",
            "#!/usr/bin/env bash\n"
            "printf 'CompileSwift FIRST-LINE\\n'\n"
            "sleep 2\n"
            "printf 'CompileC SECOND-LINE\\n'\n"
            "exit 0\n",
        )
        # Deliberately buffers all input until EOF. If xcbeautify remains in the
        # live pipeline, FIRST-LINE cannot reach the terminal promptly.
        write_executable(
            fake_bin / "xcbeautify",
            "#!/usr/bin/env bash\n"
            "cat >/dev/null\n"
            "printf 'BEAUTIFIED-AFTER-EOF\\n'\n",
        )

        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
        env["XCBUILD_LABEL"] = "streaming-contract"
        env["XCBUILD_BEAUTIFY_SUMMARY"] = "0"

        started = time.monotonic()
        proc = subprocess.Popen(
            [str(helpers / "run-xcodebuild.sh")],
            cwd=temp_root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
        )
        assert proc.stdout is not None
        try:
            first_line = proc.stdout.readline()
            elapsed = time.monotonic() - started
            remainder = proc.stdout.read()
            returncode = proc.wait(timeout=10)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()

        output = first_line + remainder
        require(first_line.strip() == "CompileSwift FIRST-LINE",
                f"first terminal line was buffered/replaced: {first_line!r}; output={output!r}")
        require(elapsed < 1.0,
                f"FIRST-LINE was not streamed promptly (elapsed={elapsed:.2f}s); xcbeautify may still be in the live pipeline")
        require("CompileC SECOND-LINE" in output, "second xcodebuild line was not streamed")
        require(returncode == 0, f"wrapper returned {returncode}; output={output!r}")



def wrapper_result_for_xcode_script(xcode_script: str) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory(prefix="relaxin-xcode-status-") as temp:
        temp_root = Path(temp)
        helpers = temp_root / "DevKit/Helpers"
        helpers.mkdir(parents=True)
        shutil.copy2(SCRIPT, helpers / "run-xcodebuild.sh")
        write_executable(temp_root / ".env.sh", "#!/usr/bin/env bash\n")
        for helper in (
            "check-tools.sh",
            "check-zstd-integration.sh",
            "check-credits-localization.sh",
            "check-engine-localization.sh",
        ):
            write_executable(helpers / helper, "#!/usr/bin/env bash\nexit 0\n")

        fake_bin = temp_root / "bin"
        fake_bin.mkdir()
        write_executable(fake_bin / "xcodebuild", xcode_script)
        # Presence of xcbeautify must not affect status propagation because it is
        # post-build and explicitly disabled in these contract cases.
        write_executable(
            fake_bin / "xcbeautify",
            "#!/usr/bin/env bash\ncat >/dev/null\nprintf 'beautified\\n'\n",
        )

        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
        env["XCBUILD_LABEL"] = "status-contract"
        env["XCBUILD_BEAUTIFY_SUMMARY"] = "0"
        return subprocess.run(
            [str(helpers / "run-xcodebuild.sh")],
            cwd=temp_root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )


def status_and_log_truth_tests() -> None:
    nonzero = wrapper_result_for_xcode_script(
        "#!/usr/bin/env bash\nprintf 'synthetic xcode failure\\n'\nexit 65\n"
    )
    require(nonzero.returncode == 65,
            f"xcodebuild exit 65 must propagate through tee; got {nonzero.returncode}; output={nonzero.stdout!r}")

    log_error = wrapper_result_for_xcode_script(
        "#!/usr/bin/env bash\nprintf 'file.swift:1:1: error: synthetic compiler failure\\n'\nexit 0\n"
    )
    require(log_error.returncode != 0,
            f"exit-0 xcodebuild with error marker must fail; output={log_error.stdout!r}")
    require("errors_in_log=1" in log_error.stdout,
            f"error marker must be attributed to saved-log scanning; output={log_error.stdout!r}")

def main() -> int:
    text = SCRIPT.read_text(encoding="utf-8")
    makefile = MAKEFILE.read_text(encoding="utf-8")

    require('tee "$RAW_LOG"' in text, "xcodebuild output must be tee'd to RAW_LOG")
    require('PIPESTATUS[@]' in text and 'pipeline_status[0]' in text, "xcodebuild exit status must come from the xcodebuild element of PIPESTATUS")
    require('>"$RAW_LOG" 2>&1' not in text, "fully-buffered redirect must remain removed")
    require('normalize_log' in text and '"$RAW_LOG" >"$LOG"' in text,
            "normalized saved log must still be produced")
    require('grep -En "$ERR_RE" "$LOG"' in text,
            "saved normalized log must still be scanned for errors")
    require('DevKit/Tests/XcodebuildStreaming/test_contract.py' in makefile,
            "streaming regression must remain part of test-host")
    require('| \\\n            xcbeautify' not in text and '| xcbeautify' not in text,
            "xcbeautify must not sit in the live xcodebuild pipeline")

    behavioral_streaming_test()
    status_and_log_truth_tests()
    print("XcodebuildStreaming contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
