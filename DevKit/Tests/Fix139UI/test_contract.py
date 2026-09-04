#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
read = lambda rel: (ROOT / rel).read_text(encoding="utf-8")

banner = read("Relaxin/Interface/Home/HomeView+TerminalContent+Layout.swift")
home = read("Relaxin/Interface/Home/HomeView.swift")

expected_bottom = 'let bannerBottom = "█▀▄ ██▄ █▄▄ █▀█ █ █ █ █ ▀█ ▀ █ █"'
assert expected_bottom in banner, "RELAXIN - X bottom row must keep the dash separated from X"

# Fix13.10 intentionally moves the quick action out of the top-right overlay.
overlay = home.split(".overlay(alignment: .topTrailing)", 1)[1].split(".alert(item:", 1)[0]
assert "EnvironmentStatusView(" in overlay, "environment status must remain visible"
assert "Button {" not in overlay, "top-right overlay must remain status-only after Fix13.10"
assert "performMenuAction(.jailbreak)" not in overlay, "top-right overlay must not own an engine action"

print("PASS Fix13.9 banner/status contract (superseded quick-action placement)")
