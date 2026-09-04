#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[3]
PBX=(ROOT/'Relaxin.xcodeproj/project.pbxproj').read_text()
fail=[]
def req(c,m):
    if not c: fail.append(m)

def phase_body(name: str) -> str:
    # Match a PBXShellScriptBuildPhase block carrying the requested name.
    pattern=re.compile(r'\n\t\t[^\n]+ /\* '+re.escape(name)+r' \*/ = \{(.*?)\n\t\t\};', re.S)
    m=pattern.search(PBX)
    if not m:
        fail.append(f'missing phase: {name}')
        return ''
    return m.group(1)

names=['Stage Generated Resources','Prepare BaseBin Headers','Prepare Exploit Dependencies']
for name in names:
    body=phase_body(name)
    for forbidden in ['/usr/bin/make','bootstrap-resources','build-basebin-resources.sh']:
        req(forbidden not in body, f'{name} still contains nested build token: {forbidden}')

stage=phase_body('Stage Generated Resources')
for marker in ['note: [Stage] bootstrap','note: [Stage] BaseBin','note: [Stage] packages','note: [Stage] finished','error: [Stage] missing prebuilt']:
    req(marker in stage, f'Stage Generated Resources missing marker: {marker}')

for name in ['Prepare BaseBin Headers','Prepare Exploit Dependencies']:
    body=phase_body(name)
    req('error: [Prebuild]' in body, f'{name} must fail fast with a prebuild error')

if fail:
    print('Xcode prebuilt-resource boundary contract: FAIL', file=sys.stderr)
    for x in fail: print('- '+x, file=sys.stderr)
    raise SystemExit(1)
print('Xcode prebuilt-resource boundary contract: PASS')
