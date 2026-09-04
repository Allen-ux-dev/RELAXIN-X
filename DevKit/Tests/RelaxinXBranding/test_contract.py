#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]

def text(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')

pbx = text('Relaxin.xcodeproj/project.pbxproj')
build = text('BuildIPA.command')
terminal = text('Relaxin/Interface/Home/HomeView+TerminalContent+Layout.swift')
credits = text('Relaxin/Interface/Home/HomeView+Credits.swift')
readme = text('README.md')
log_export = text('Relaxin/Backend/Logging/AppLog+Export.swift')
maintenance = text('Relaxin/Interface/Home/HomeView+Maintenance.swift')
status_view = text('Relaxin/Interface/Home/EnvironmentStatusView.swift')
localizable = text('Relaxin/Resources/Localizable.xcstrings')

assert pbx.count('INFOPLIST_KEY_CFBundleDisplayName = "RELAXIN-X";') == 2, 'full app display name must be RELAXIN-X in Debug and Release'
assert pbx.count('INFOPLIST_KEY_CFBundleDisplayName = "RELAXIN-X Lite";') == 2, 'lite app display name must be RELAXIN-X Lite'

assert 'OUTPUT_IPA="$OUTPUT_DIR/RELAXIN-X.ipa"' in build, 'BuildIPA output must use RELAXIN-X.ipa'
assert 'STAGING_IPA="$STAGING_DIR/RELAXIN-X.ipa"' in build, 'staging IPA must use RELAXIN-X.ipa'
assert 'step "RELAXIN-X IPA Build"' in build, 'build banner must use RELAXIN-X'
assert 'TEMP_SHA256="$STAGING_DIR/RELAXIN-X.ipa.sha256.txt"' in build, 'checksum filename must use RELAXIN-X'

assert 'let bannerTop = ' in terminal and 'let bannerBottom = ' in terminal, 'terminal home must render the RELAXIN-X half-block banner'
assert 'runtime framework' not in terminal.lower(), 'upstream-style banner must not carry the compact runtime-framework subtitle'
assert 'let bannerTop = "█▀█ █▀▀ █   ▄▀█ ▀▄▀ █ █▄ █' in terminal, 'home must restore the upstream Relaxin half-block banner'
assert 'let bannerBottom = "█▀▄ ██▄ █▄▄ █▀█ █ █ █ █ ▀█' in terminal, 'home must restore the upstream Relaxin lower banner row'
assert '▀▄▀' in terminal, 'RELAXIN-X banner must extend the upstream mark with a half-block X glyph'
assert '.thinMaterial' not in status_view, 'status surface should use the cleaner terminal-like panel rather than a glass material card'
assert 'strokeBorder' in status_view, 'status surface should retain a subtle terminal-like outline'

# Maintainer must be a dedicated block, not one entry mixed into upstream credits.
assert 'RELAXIN-X Maintainer' in credits, 'credits must have a dedicated RELAXIN-X maintainer section'
assert 'Allen-ux-dev' in credits, 'credits must identify the maintainer by GitHub handle'
assert 'https://github.com/Allen-ux-dev' in credits, 'credits must link the maintainer GitHub profile'
assert credits.count('https://github.com/Allen-ux-dev') == 1, 'maintainer GitHub link should appear once in app credits'
assert 'Original Relaxin / Upstream' in credits, 'upstream credits must remain explicitly separated'
assert credits.index('RELAXIN-X Maintainer') < credits.index('Original Relaxin / Upstream'), 'maintainer block must be pulled out ahead of upstream roster'
assert 'secondary: "Zebra Integration"' not in credits, 'maintainer must no longer be represented as only a Zebra integration roster entry'

assert readme.startswith('# RELAXIN-X\n'), 'README title must use RELAXIN-X'
assert '## RELAXIN-X Maintainer' in readme, 'README must give maintainer a dedicated section'
assert '[Allen-ux-dev](https://github.com/Allen-ux-dev)' in readme, 'README maintainer identity must use GitHub only'
assert '## Original Relaxin / Upstream' in readme, 'README must preserve separated upstream attribution'

assert 'RELAXIN-X-Logs-' in log_export, 'exported log archives must use RELAXIN-X branding'
assert 'RELAXIN-X-Diagnostics-' in maintenance, 'diagnostics directories must use RELAXIN-X branding'

for old in [
    'Close Relaxin, reopen it, and try again.',
    'Removing the jailbreak. Keep Relaxin in the foreground.',
    'Jailbreak removal is complete. Tap OK to close Relaxin.',
    'Reset Relaxin',
    'Relaxin Reset',
    'Relaxin settings and caches were cleared.',
    'Relaxin Lite requires an active RootHide jailbreak.',
]:
    assert old not in localizable, f'old user-facing brand remains in string catalog: {old}'

for new in [
    'Close RELAXIN-X, reopen it, and try again.',
    'Removing the jailbreak. Keep RELAXIN-X in the foreground.',
    'Jailbreak removal is complete. Tap OK to close RELAXIN-X.',
    'Reset RELAXIN-X',
    'RELAXIN-X Reset',
    'RELAXIN-X settings and caches were cleared.',
    'RELAXIN-X Lite requires an active RootHide jailbreak.',
]:
    assert new in localizable, f'new user-facing brand missing from string catalog: {new}'

print('RELAXIN-X branding contract: PASS')
