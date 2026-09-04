#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / 'DevKit/Helpers/build-home.sh'
BUILDIPA = ROOT / 'BuildIPA.command'


def bash_eval(script: str, *args: str) -> str:
    cmd = ['bash', '-lc', script, 'bash', *args]
    return subprocess.check_output(cmd, text=True).strip()


def make_source(path: Path, marker: str = 'one') -> None:
    path.mkdir(parents=True)
    shutil.copy2(ROOT / 'SOURCE_BASE.txt', path / 'SOURCE_BASE.txt')
    shutil.copy2(ROOT / 'ZEBRA_INTEGRATION.md', path / 'ZEBRA_INTEGRATION.md')
    (path / 'Example.swift').write_text(marker + '\n')
    (path / 'DeleteMe.txt').write_text('delete me\n')


def cache_key(source: Path, xcode: str, sdk: str) -> str:
    return bash_eval(
        'source "$1"; relaxin_cache_key "$2" "$3" "$4"',
        str(HELPER), str(source), xcode, sdk,
    )


def sync(source: Path, dest: Path) -> None:
    subprocess.check_call([
        'bash', '-lc',
        'source "$1"; relaxin_sync_workspace "$2" "$3"',
        'bash', str(HELPER), str(source), str(dest),
    ])


def main() -> None:
    assert HELPER.exists(), 'missing DevKit/Helpers/build-home.sh'

    with tempfile.TemporaryDirectory(prefix='relaxin stable workspace ') as tmp:
        base = Path(tmp)
        source_a = base / 'Relaxin Source A'
        source_b = base / 'Totally Different Folder Name'
        workspace = base / 'cache-home' / 'workspace' / 'source'
        make_source(source_a)
        make_source(source_b)

        key_a = cache_key(source_a, '17F113', '26.5')
        key_b = cache_key(source_b, '17F113', '26.5')
        assert key_a == key_b, (key_a, key_b)
        assert cache_key(source_a, '17F114', '26.5') != key_a
        assert cache_key(source_a, '17F113', '26.6') != key_a

        sync(source_a, workspace)
        assert (workspace / 'Example.swift').read_text() == 'one\n'
        assert (workspace / 'DeleteMe.txt').exists()

        sentinel = workspace / 'build' / 'cache-sentinel.txt'
        sentinel.parent.mkdir(parents=True, exist_ok=True)
        sentinel.write_text('keep\n')

        (source_a / 'Example.swift').write_text('two-updated\n')
        (source_a / 'DeleteMe.txt').unlink()
        sync(source_a, workspace)

        assert (workspace / 'Example.swift').read_text() == 'two-updated\n'
        assert not (workspace / 'DeleteMe.txt').exists()
        assert sentinel.read_text() == 'keep\n'

    text = BUILDIPA.read_text()
    assert 'relaxin-zebra-source.XXXXXX' not in text
    assert 'RELAXIN_BUILD_HOME' in text
    assert 'RELAXIN_WORKSPACE_SOURCE' in text
    assert 'RELAXIN_DERIVED_DATA' in text
    assert 'RELAXIN_BUILD_LOCK_DIRECTORY' in text
    assert 'acquire_build_lock' in text
    assert 'Build.lock' in text

    print('BuildIPA stable-workspace contract: PASS')


if __name__ == '__main__':
    main()
