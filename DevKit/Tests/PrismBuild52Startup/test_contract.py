from pathlib import Path

root = Path(__file__).resolve().parents[3]
endpoint = root / "Relaxin/Backend/PrismRuntimeBridge/PrismBuild52RuntimeEndpoint.swift"
bootstrap = root / "Relaxin/Backend/PrismRuntimeBridge/PrismRuntimeBridgeBootstrap.swift"
app = (root / "Relaxin/Application/RelaxinApp.swift").read_text()
lite = (root / "Configuration/Targets/RelaxinLite.xcconfig").read_text()

assert endpoint.exists(), "missing PrismBuild52RuntimeEndpoint.swift"
endpoint_text = endpoint.read_text()
assert "/var/run/relaxinx-runtime.sock" in endpoint_text
assert "RELAXINX_PRISM_RUNTIME_SOCKET" in endpoint_text

assert bootstrap.exists(), "missing PrismRuntimeBridgeBootstrap.swift"
bootstrap_text = bootstrap.read_text()
assert "PrismUnixSocketRuntimeServiceServer" in bootstrap_text
assert "makeHandshakeOnlyHost" in bootstrap_text
assert "PrismRuntimeBridgeBootstrap.shared.start" in app
assert "AppLog.error" in app
assert "PrismBuild52RuntimeEndpoint.swift" in lite
assert "PrismRuntimeBridgeBootstrap.swift" in lite

for text in (endpoint_text, bootstrap_text):
    assert "/var/run/prismd.sock" not in text

print("PASS: Prism Build 52 startup bridge contract")
