#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
read = lambda rel: (ROOT / rel).read_text(encoding="utf-8")

home = read("Relaxin/Interface/Home/HomeView.swift")
menu = read("Relaxin/Interface/Home/HomeView+Menu.swift")
screen = read("Relaxin/Interface/Home/HomeView+Screen.swift")
content = read("Relaxin/Interface/Home/HomeView+Content.swift")
options = read("Relaxin/Interface/Components/OptionList/OptionList.swift")
terminal = read("Relaxin/Interface/Home/HomeView+TerminalContent.swift")
layout = read("Relaxin/Interface/Home/HomeView+TerminalContent+Layout.swift")

# RELAXIN - X remains separated while staying in the upstream half-block style.
assert 'let bannerBottom = "█▀▄ ██▄ █▄▄ █▀█ █ █ █ █ ▀█ ▀ █ █"' in layout

# The mistaken Fix13.9 top-right action is gone; only status stays there.
overlay = home.split('.overlay(alignment: .topTrailing)', 1)[1].split('.alert(item:', 1)[0]
assert 'EnvironmentStatusView(' in overlay
assert 'Button {' not in overlay, "top-right environment overlay must not contain Start Jailbreak"
assert 'performMenuAction(.jailbreak)' not in overlay

# Home menu order is stable: Start Jailbreak immediately above Environment Check.
menu_entries = screen.split('func menuEntries(', 1)[1]
home_branch = menu_entries.split('case .home:', 1)[1].split('case .advancedOptions:', 1)[0]
assert home_branch.index('.jailbreak,') < home_branch.index('.environmentCheck,')
assert 'String(localized: "Start Jailbreak"' in home_branch

# Environment routing may add recovery actions, but must not replace/remove Start Jailbreak.
assert 'entries[jailbreakIndex] = (.jailbreak, jailbreakMenuTitle)' in menu
assert 'entries[jailbreakIndex] = (\n                    .restoreEnvironment' not in menu
assert 'entries[jailbreakIndex] = (\n                    .repairEnvironment' not in menu
assert 'entries.remove(at: jailbreakIndex)' not in menu
assert 'recoveryMenuAction' in menu

# Disabled actions are first-class so Start Jailbreak can stay visible without bypassing admission.
assert 'disabledMenuActions' in home
assert 'disabledMenuActions: disabledMenuActions' in home
assert 'disabledMenuActions' in content
assert 'disabledActions:' in options
assert '.disabled(isLoading || isDisabled)' in options
assert 'disabledMenuActions' in menu

# Environment Check shows its live state and cannot be triggered twice while inspecting.
assert 'environmentCheckMenuTitle' in menu
assert 'environmentStatusTitle' in menu
assert 'engineSession.environmentState == .inspecting' in menu
assert 'actions.insert(.environmentCheck)' in menu

# Start Jailbreak shows a reason when disabled and still uses the existing action path.
assert 'jailbreakMenuTitle' in menu
assert 'canStartHomeJailbreak' in menu
assert 'case .jailbreak:' in menu and 'startEngine()' in menu

# Home terminal exposes the selected package managers without changing engine execution.
assert 'packageManagerSummary' in home
assert 'packageManagerSummary: packageManagerSummary' in home
assert 'packageManagerSummary: String?' in terminal
assert '("packages", packageManagerSummary)' in terminal

print("PASS Fix13.10 home-flow UI source contract")
