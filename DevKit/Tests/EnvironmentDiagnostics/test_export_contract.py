from pathlib import Path

root = Path(__file__).resolve().parents[3]
maintenance = (root / "Relaxin/Interface/Home/HomeView+Maintenance.swift").read_text(errors="replace")
exporter = (root / "Relaxin/Backend/Logging/AppLog+Export.swift").read_text(errors="replace")

assert "environmentDiagnosticJSON()" in maintenance
assert "environment-diagnostics.json" in maintenance
assert "supplementalFiles:" in maintenance
assert "supplementalFiles:" in exporter
assert "files + supplementalFiles" in exporter or "supplementalFiles + files" in exporter
assert "removeItem(at: diagnosticURL)" in maintenance

print("ok environment-diagnostics-export-contract")
