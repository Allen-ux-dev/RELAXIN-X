#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
read = lambda rel: (ROOT / rel).read_text(encoding="utf-8")

banner = read("Relaxin/Interface/Home/HomeView+TerminalContent+Layout.swift")
content = read("Relaxin/Interface/Home/HomeView+Content.swift")
layout = read("Relaxin/Interface/Home/HomeView+Content+Layout.swift")
credits = read("Relaxin/Interface/Home/HomeView+Credits.swift")
home = read("Relaxin/Interface/Home/HomeView.swift")
post_home = read("Relaxin/Interface/PostJailbreak/PostJailbreakHomeView.swift")
home_screen = read("Relaxin/Interface/Home/HomeView+Screen.swift")
post_screen = read("Relaxin/Interface/PostJailbreak/PostJailbreakHomeView+Menu.swift")
options = read("Relaxin/Interface/Components/OptionList/OptionList.swift")
boot_white = read("Relaxin/Resources/Assets.xcassets/BootLogoMark.imageset/BootLogoMarkWhite.svg")
boot_black = read("Relaxin/Resources/Assets.xcassets/BootLogoMark.imageset/BootLogoMarkBlack.svg")

assert 'let bannerTop = "█▀█ █▀▀ █   ▄▀█ ▀▄▀ █ █▄ █' in banner
assert 'let bannerBottom = "█▀▄ ██▄ █▄▄ █▀█ █ █ █ █ ▀█' in banner
assert 'runtime framework' not in banner.lower()
assert 'package manager supported in this build' not in banner
assert '   ▀▄▀"' in banner and ' ▀ █ █"' in banner, 'banner suffix must render the approved spaced half-block - X mark'
assert 'TerminalStyle.bold(bannerTop)' in banner and 'TerminalStyle.bold(bannerBottom)' in banner

assert 'HomeContentLayout.minimumMenuLayoutHeight(' in content and 'terminalHeight: terminalHeight' in content
assert 'compact' in content.lower()
assert 'ScrollViewReader' in content and 'ScrollView' in content
assert 'minimumMenuLayoutHeight(terminalHeight:' in layout
assert '.fixedSize(horizontal: false, vertical: true)' in options

assert 'terminalWidth: Int' in credits

terminal_content = read("Relaxin/Interface/Home/HomeView+TerminalContent.swift")
credits_call = terminal_content.split("+ RelaxinCredits.terminalLines(", 1)[1].split(").joined(separator:", 1)[0]
assert "terminalWidth: terminalWidth" in credits_call, "credits must forward terminalWidth into RelaxinCredits.terminalLines"
assert 'lineCount(terminalWidth:' in credits
assert 'terminalWidth: terminalColumnCount' in home
assert 'HomeContentLayout.creditsTerminalHeight(' in home and 'lineCount: RelaxinCredits.lineCount(' in home
assert 'HomeContentLayout.creditsTerminalHeight(' in post_home and 'lineCount: RelaxinCredits.lineCount(' in post_home
assert 'HomeContentLayout.creditsTerminalHeight' not in home_screen and 'HomeContentLayout.creditsTerminalHeight' not in post_screen

for svg in (boot_white, boot_black):
    assert 'Half-block "X"' in svg
    assert 'Half-block "R"' not in svg
    assert 'x="422" y="332"' in svg, 'X center pixel must be present'
    assert 'x="242" y="512"' in svg and 'x="602" y="512"' in svg, 'X lower legs must be present'

print("PASS Fix13.7 UI source contract")
