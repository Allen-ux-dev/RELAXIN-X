import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
strings = json.loads((root / "Relaxin/Resources/Localizable.xcstrings").read_text())["strings"]
required_locales = {"ar", "de", "en", "es", "fr", "ja", "ru", "vi", "zh-Hans"}
keys = [
    "Stealth Compatibility",
    "Environment",
    "Compatibility profiles are suspended until the jailbreak runtime is restored.",
    "Needs Review",
    "Applications",
    "No application profiles are configured.",
    "Add Application",
    "Bundle Identifier",
    "Add Compatibility Profile",
    "Compatibility Profile",
    "Protected management application",
    "Mode",
    "Repair Compatibility",
    "Ready",
    "Suspended",
    "Degraded",
    "Automatic",
    "Compatibility",
    "Developer",
    "Disabled",
    "Compatibility profiles reduce accidental jailbreak-environment exposure for ordinary apps. Management and development components stay outside compatibility isolation.",
]
for key in keys:
    assert key in strings, f"missing Stealth localization key: {key}"
    locales = set(strings[key].get("localizations", {}))
    missing = required_locales - locales
    assert not missing, f"{key} missing locales: {sorted(missing)}"

view = (root / "Relaxin/Interface/Settings/StealthCompatibilityView.swift").read_text(errors="replace")
assert "String(localized:" in view, "Stealth settings must use the runtime resource bundle explicitly"
assert 'Text(\n                    "Compatibility profiles reduce' not in view, "dynamic explanatory String must not bypass localization"

print("ok stealth-localization-contract")
