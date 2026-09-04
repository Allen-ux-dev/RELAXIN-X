# Build RELAXIN-X IPA

On a Mac with the full Xcode installation, double-click `BuildIPA.command`.
The output remains an **unsigned** IPA; the helper does not embed a signing identity or provisioning profile.

Fix11 changes the build orchestration so repeated builds reuse a stable workspace, Xcode DerivedData, HostTools, Bootstrap resources, and BaseBin resources instead of rebuilding from a random temporary source path every time.

## Build home

For a given RELAXIN-X source identity and active Xcode/iPhoneOS SDK, `BuildIPA.command` derives a stable cache key and uses:

```text
~/Library/Caches/RelaxinBuild/<cache-key>/
├── workspace/source/
├── DerivedData/
├── HostTools/
├── BaseBin/
│   ├── CompilerCache/
│   └── Resources/
├── Bootstrap/
│   ├── Sources/
│   ├── Resources/
│   └── Tools/
├── Locks/
└── Logs/
```

The cache key is based on `SOURCE_BASE.txt`, the Zebra integration identity, the active Xcode build version, and the iPhoneOS SDK version. It does **not** contain the original source-folder path, so re-extracting the same source package as `RELAXIN-X-FullSource 2` or `... 3` reuses the same compatible build home.

Changing Xcode or the iPhoneOS SDK selects a different cache key automatically.

The internal cache directory intentionally remains `~/Library/Caches/RelaxinBuild` so RELAXIN-X reuses existing Fix11+ warm caches instead of forcing an expensive Bootstrap/BaseBin rebuild after the rebrand.

A build-wide PID lock under `Locks/Build.lock` serializes writes to one cache home. If the recorded owner PID no longer exists, the stale lock is removed automatically.

## Stable workspace and source paths containing spaces

The original source directory is authoritative. Before each build, Fix11 runs an incremental `rsync --delete` into the stable `workspace/source` path. Generated state is excluded from synchronization:

- `build/`
- `Output/`
- `DerivedData/`
- `.git/`
- `.DS_Store`

This means a Downloads directory containing spaces is no longer passed to GNU Make/Xcode, but the build workspace also no longer changes to a random `relaxin-zebra-source.XXXXXX` directory on every run.

Deleted source files are deleted from the stable workspace on the next synchronization. Build caches under the workspace `build/` directory survive the sync.

The final verified IPA is still atomically published back to the original source directory under `Output/`.

## Host-tool preflight

Before resource preparation, the helper verifies the tools used by Make/Xcode/BaseBin:

- Xcode + iPhoneOS SDK
- `rg` / ripgrep
- `zstd`
- `gtar`
- `dpkg-deb`
- `ldid`
- `trustcache`
- `git`, `rsync`, `shasum`
- GNU Make

Homebrew mappings remain:

- `rg` -> `ripgrep`
- `zstd` -> `zstd`
- `gtar` -> `gnu-tar`
- `dpkg-deb` -> `dpkg`
- `ldid` -> `ldid`

### trustcache

A compatible `trustcache` v2.0 is stored under the stable build home at `HostTools/bin/trustcache`. The pinned source remains `CRKatri/trustcache` commit `aa0e8847529cf76576fce8d2dbc9e088c8f1a0df` and is built with the active macOS SDK plus Homebrew `libmd` when necessary.

Fix11 can copy a valid old source-local `build/HostTools/bin/trustcache` into the build home on first use. Later builds reuse the build-home copy.

## Resource prebuild boundary

Expensive resource work now happens **before xcodebuild starts**:

```text
== Preparing Bootstrap ==
cache hit or prepare/verify

== Preparing BaseBin ==
cache hit or build/verify

== Verifying prebuilt resources ==
all required resources ready

== Building unsigned IPA ==
xcodebuild
```

`Stage Generated Resources`, `Prepare BaseBin Headers`, and `Prepare Exploit Dependencies` no longer launch Bootstrap/BaseBin builds from inside Xcode. They only assert that prebuilt resources exist and stage/copy them.

A direct Xcode build that bypasses the prebuild boundary fails quickly with an `error: [Prebuild] ... run BuildIPA.command first` message instead of silently starting an expensive nested build.

### Bootstrap cache

The downloaded source archive, prepared archive, and `VerifyAdHocSignature` helper live under `Bootstrap/`. Existing safe Fix9/Fix10 Bootstrap state may be copied into the Fix11 build home; old state is not deleted during migration.

A cache hit prints:

```text
note: [Bootstrap] resources are up to date
```

A real preparation continues to print extraction, Mach-O scan/signing, archive rebuilding, zstd compression, verification, and completion progress.

### BaseBin cache

The compiler/module cache has one stable physical path under `BaseBin/CompilerCache`, so Swift/Clang PCM files no longer see a different `relaxin-zebra-source.XXXXXX` path on every run.

Published artifacts live under `BaseBin/Resources`. The BaseBin helper still calculates its full input fingerprint and validates `.artifact-sha256` before accepting a hit. A hit is accepted only when the staged BaseBin header tree also exists; if working headers were deliberately cleaned, BaseBin reconstructs its working state rather than handing Xcode a resource-only cache hit.

A valid hit prints:

```text
note: [BaseBin] resources are up to date
```

Fix8-Fix10 compiler/PCM caches are intentionally not imported.

## Incremental Xcode DerivedData

Normal `BuildIPA.command` runs do **not** call `make clean` and do not delete Xcode DerivedData. Xcode uses:

```text
~/Library/Caches/RelaxinBuild/<cache-key>/DerivedData
```

This allows a second unchanged build to reuse Xcode's dependency graph, module state, and compiled outputs rather than recreating the entire build from a clean DerivedData directory.

For an intentional clean build, run:

```bash
./BuildIPA.command --clean
```

Clean mode removes the current cache key's DerivedData and BaseBin working/resources state before rebuilding. It does not delete a previously verified IPA in the original `Output/` directory.

## Terminal output and full logs

The default xcodebuild view is live but concise. It shows major compile/link/copy actions, Run Script phases, `[Stage]`/`[Prebuild]` progress, warnings, errors, and build success/failure markers. Large `export NAME=value` Run Script environment dumps are hidden from the default terminal view.

The complete unmodified xcodebuild transcript is always retained under:

```text
~/Library/Caches/RelaxinBuild/<cache-key>/Logs/
```

On failure the wrapper prints the raw-log path, normalized-log path, build-home path, and workspace path, then shows the first relevant error lines.

To print the entire raw xcodebuild stream live as well, run with:

```bash
XCBUILD_VERBOSE=1 ./BuildIPA.command
```

`xcbeautify` is never placed in the live producer pipeline, so a buffering formatter cannot block xcodebuild output.

## IPA validation and publication

After Xcode succeeds, the existing validation remains mandatory:

1. the IPA must be a valid ZIP;
2. exactly one top-level `Payload/*.app/Info.plist` must exist;
3. the declared main executable must exist;
4. `_CodeSignature` must not be present;
5. `embedded.mobileprovision` must not be present;
6. macOS metadata must not be present.

Only after all checks pass is the staged IPA moved to:

```text
Output/RELAXIN-X.ipa
Output/RELAXIN-X.ipa.sha256.txt
```

A failed dependency check, prebuild, Xcode build, or IPA validation leaves a previously published successful IPA untouched.

## What to expect on repeated builds

The first Fix11 build may still be relatively expensive because it creates a fresh Fix11 DerivedData/BaseBin working state. With unchanged source and toolchain, the next build should keep the **same printed build-home/workspace path**, reuse trustcache, print Bootstrap/BaseBin cache hits, avoid deleting DerivedData, and make `Stage Generated Resources` a short copy-only phase.
