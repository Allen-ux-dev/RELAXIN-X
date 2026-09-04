# Sileo

`sileo.deb` is downloaded byte-for-byte from the RootHide APT repository:

- Repository: <https://roothide.github.io/>
- Index: <https://roothide.github.io/Packages>
- Package file: <https://roothide.github.io/debfiles/org.coolstar.sileo_2.5.1-13_iphoneos-arm64e.deb>
- Package: `org.coolstar.sileo`
- Version: `2.5.1-13`
- Debian architecture: `iphoneos-arm64e`
- Size: `3946984` bytes
- SHA-256: `b23e51371938bb6257ba82abdcdae9a6519755556b874b06672868c64843a0f6`

The package is vendored without local modifications. Its `Sileo` and
`giveMeRoot` Mach-O executables are thin `arm64`.

Update it manually with `DevKit/Helpers/update-sileo.sh [VERSION]`. Pass
`--reference PATH` when the current deb must first match another project.

## Bundled third-party licenses

`Sileo.app/Licenses.plist` from the deb is preserved as `BundledLicenses.plist`
(renamed so the license aggregator does not ingest the binary plist). The same
texts are also split beside the tree under `Dependencies/`:

| Component | License | Role |
| --- | --- | --- |
| Cosmos | MIT | Direct Sileo dependency |
| Down | MIT | Direct Sileo dependency (Markdown) |
| LNZTreeView | MIT | Direct Sileo dependency |
| SQLite.swift | MIT | Direct Sileo dependency |
| cmark | BSD-2-Clause | Nested via Down |
| houdini | MIT | Nested via cmark |
| cmark-buffer | MIT | Nested via cmark (GitHub, Inc.) |
| utf8proc | MIT | Nested via cmark |
| markdowntest | MIT | Nested via cmark test normalization |
| cmark-tests | BSD-2-Clause | Nested via cmark tests |
| CommonMark-spec | CC-BY-SA 4.0 | Nested via cmark spec text |

Debian `Depends` such as `apt`, `dpkg`, `libzstd1`, and `coreutils` are
runtime packages on the jailbroken device; they are not vendored as source
here. Relaxin's separate `Vendor/zstd` snapshot is unrelated to the Sileo
package payload.
