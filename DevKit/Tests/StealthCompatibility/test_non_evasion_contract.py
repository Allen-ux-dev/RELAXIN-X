from pathlib import Path
root = Path(__file__).resolve().parents[3]
stealth = root/'Relaxin/Backend/StealthCompatibility'
assert stealth.exists(), 'StealthCompatibility sources must exist'
files = sorted(stealth.glob('*.swift'))
files += [
    root/'RelaxinPostJailbreak/Actions/RLXCompatibilityProfileAction.m',
    root/'RelaxinPostJailbreak/Controller/RLXPostJailbreakController.m',
]
assert files, 'StealthCompatibility sources must exist'
text = '\n'.join(p.read_text(errors='replace') for p in files).lower()
for forbidden in [
    'anti-cheat bypass',
    'anticheat bypass',
    'mdm bypass',
    'edr bypass',
    'bank bypass',
    'fake jailbreak status',
    'syscall return spoof',
    'detection bypass',
]:
    assert forbidden not in text, f'forbidden scope drift token: {forbidden}'
assert 'compatibility/privacy boundary' in text
assert 'security controls' in text
assert 'global syscall' in text
print('ok stealth-non-evasion-contract')
