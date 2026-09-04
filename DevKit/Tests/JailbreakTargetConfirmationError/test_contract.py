from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
path = root / 'Relaxin/Backend/JailbreakConfiguration/JailbreakTarget.swift'
text = path.read_text()

# The nested ConfirmationError type must explicitly name the outer JailbreakTarget
# when calling the outer hex helper. `Self` inside the nested enum resolves to
# JailbreakTarget.ConfirmationError and does not have `hex`.
match = re.search(r'enum ConfirmationError: Error \{(?P<body>.*?)\n    \}\n\n    static let current', text, re.S)
assert match, 'could not locate ConfirmationError body'
body = match.group('body')
assert 'Self.hex(' not in body, 'ConfirmationError must not resolve outer helpers through nested Self'
assert 'JailbreakTarget.hex(cpuFamily)' in body, 'unsupportedSoC must use the outer JailbreakTarget hex helper explicitly'

# Preserve the outer type's valid Self.hex usage; the fix should stay narrowly scoped.
outer_without_error = text[:match.start()] + text[match.end():]
assert outer_without_error.count('Self.hex(') >= 2, 'outer JailbreakTarget Self.hex usage should remain intact'
print('PASS JailbreakTargetConfirmationError contract')
