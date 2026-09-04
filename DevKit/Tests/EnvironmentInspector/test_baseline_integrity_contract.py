from pathlib import Path

root = Path(__file__).resolve().parents[3]
swift = (root / "Relaxin/Backend/EnvironmentRecovery/EnvironmentInspector.swift").read_text()
metadata = (root / "Relaxin/Backend/RuntimeAbstraction/KernelProfileIntegrityMetadata.swift").read_text()
evaluator = (root / "Relaxin/Backend/RuntimeAbstraction/BaselineIntegrityEvaluator.swift").read_text()

assert "KernelProfileIntegrityMetadata.load(" in swift
assert "BaselineIntegrityEvaluator.evaluate(" in swift
assert "upstreamBaselineID: baseline.id" in swift
assert "availableBaselineIntegrity: integrity.availableRequirements" in swift
assert "PropertyListSerialization.propertyList" in metadata
assert "Data(contentsOf:" in metadata

# Production inspection remains bundle-local/read-only. The baseline path must not
# execute binaries, invoke shell commands, or write back to the offset table.
for forbidden in ["Process()", "NSTask", "write(to:", "FileHandle(forWriting", "removeItem", "moveItem"]:
    assert forbidden not in metadata, f"metadata loader must remain read-only: {forbidden}"
for forbidden in ["Process()", "NSTask", "write(to:", "FileHandle(forWriting"]:
    assert forbidden not in evaluator, f"integrity evaluator must remain pure: {forbidden}"

print("ok environment-inspector-baseline-integrity-contract")
