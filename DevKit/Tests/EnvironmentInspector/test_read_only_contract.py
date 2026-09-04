from pathlib import Path

root = Path(__file__).resolve().parents[3]
bootstrap_impl = root / "RelaxinEngine/Inspection/RLXBootstrapEnvironmentInspector.m"
bootstrap_header = root / "RelaxinEngine/Inspection/RLXBootstrapEnvironmentInspector.h"
package_impl = root / "RelaxinPostJailbreak/Inspection/RLXPackageManagerHealthInspector.m"
package_header = root / "RelaxinPostJailbreak/Inspection/RLXPackageManagerHealthInspector.h"
controller_header = root / "RelaxinPostJailbreak/Controller/RLXPostJailbreakController.h"
controller_impl = root / "RelaxinPostJailbreak/Controller/RLXPostJailbreakController.m"

for path in [bootstrap_impl, bootstrap_header, package_impl, package_header]:
    assert path.exists(), f"missing {path.relative_to(root)}"

text = bootstrap_impl.read_text()
for forbidden in [
    "removeItemAtPath:",
    "moveItemAtPath:",
    "chmod(",
    "chown(",
    "rerandom",
    "publish",
    "install_pkg",
    "scanJailbreakRootsWithInstalledRoot",
]:
    assert forbidden not in text, f"read-only bootstrap inspector contains forbidden token {forbidden}"

bootstrap_header_text = bootstrap_header.read_text()
assert "inspectContainerRoots" in bootstrap_header_text
assert "inspectSystemContainerRootsWithError" in bootstrap_header_text
assert "candidateCount" in bootstrap_header_text
assert "hasInstalledRelaxinMarker" in bootstrap_header_text

# A normal RootHide topology may expose the same .jbroot brand in both container roots.
# Candidate count is by brand/name, not by physical path, or a valid install looks ambiguous.
assert "candidateNames.count" in text, "bootstrap candidates must be deduplicated across primary/secondary roots"
assert "incompatibleMarkers" in text, "inspector must report conflicting bootstrap markers read-only"
assert "conflicting_marker" in text, "conflicting markers must be surfaced as evidence"

package_text = package_impl.read_text()
for forbidden in ["removeItemAtPath:", "writeToFile:", "install_pkg", "reinstall", "launchApplication"]:
    assert forbidden not in package_text, f"package health inspector mutates state via {forbidden}"
package_header_text = package_header.read_text()
assert "sileoHealthy" in package_header_text
assert "zebraHealthy" in package_header_text

controller_h = controller_header.read_text()
controller_m = controller_impl.read_text()
assert "RLXPostJailbreakRuntimeEvidence" in controller_h
assert "runtimeEvidence" in controller_h
assert "rootHideReportedJailbroken" in controller_m
assert "processRuntimeActive" in controller_m
assert "processIsPlatform" in controller_m

print("ok environment-inspector-read-only-contract")
