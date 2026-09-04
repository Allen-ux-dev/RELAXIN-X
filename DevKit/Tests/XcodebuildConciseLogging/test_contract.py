#!/usr/bin/env python3
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[3]
SCRIPT=ROOT/'DevKit/Helpers/run-xcodebuild.sh'
MAKE=ROOT/'Makefile'

def write_exec(path: Path, text: str):
    path.write_text(text)
    path.chmod(0o755)

def fixture():
    temp=tempfile.TemporaryDirectory(prefix='relaxin concise log ')
    root=Path(temp.name)
    helpers=root/'DevKit/Helpers'; helpers.mkdir(parents=True)
    shutil.copy2(SCRIPT, helpers/'run-xcodebuild.sh')
    write_exec(root/'.env.sh', '#!/usr/bin/env bash\n')
    for name in ['check-tools.sh','check-zstd-integration.sh','check-credits-localization.sh','check-engine-localization.sh']:
        write_exec(helpers/name, '#!/usr/bin/env bash\nexit 0\n')
    fake=root/'bin'; fake.mkdir()
    return temp, root, helpers, fake

def main():
    temp, root, helpers, fake=fixture()
    try:
        write_exec(fake/'xcodebuild', '''#!/usr/bin/env bash
printf 'export ACTION=build\\n'
printf 'CompileSwift FIRST-LINE\\n'
sleep 2
printf 'warning: sample warning\\n'
printf 'export SDKROOT=/fake\\n'
printf 'PhaseScriptExecution Stage Generated Resources\\n'
printf 'error: sample error\\n'
exit 0
''')
        logdir=root/'logs'; logdir.mkdir()
        env=os.environ.copy(); env['PATH']=f"{fake}:{env.get('PATH','')}"
        env['XCBUILD_LABEL']='concise-contract'; env['XCBUILD_LOG_DIR']=str(logdir)
        started=time.monotonic()
        proc=subprocess.Popen([str(helpers/'run-xcodebuild.sh')], cwd=root, env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1)
        assert proc.stdout is not None
        first=proc.stdout.readline(); elapsed=time.monotonic()-started
        rest=proc.stdout.read(); rc=proc.wait(timeout=10); output=first+rest
        assert first.strip() == 'CompileSwift FIRST-LINE', output
        assert elapsed < 1.0, elapsed
        assert 'export ACTION=build' not in output
        assert 'export SDKROOT=/fake' not in output
        assert 'warning: sample warning' in output
        assert 'PhaseScriptExecution Stage Generated Resources' in output
        assert 'error: sample error' in output
        assert rc != 0
        raw=list(logdir.glob('concise-contract-*.raw.log'))
        assert len(raw)==1, list(logdir.iterdir())
        raw_text=raw[0].read_text()
        for line in ['export ACTION=build','CompileSwift FIRST-LINE','warning: sample warning','export SDKROOT=/fake','PhaseScriptExecution Stage Generated Resources','error: sample error']:
            assert line in raw_text, (line, raw_text)
    finally:
        temp.cleanup()

    text=SCRIPT.read_text()
    assert 'XCBUILD_LOG_DIR' in text
    assert 'XCBUILD_VERBOSE' in text
    assert 'trap \'rm -f "$RAW_LOG" "$LOG"\' EXIT' not in text
    assert 'DevKit/Tests/XcodebuildConciseLogging/test_contract.py' in MAKE.read_text()
    print('Xcodebuild concise-logging contract: PASS')

if __name__=='__main__':
    main()
